/* smc_improved.c
 *
 * Improved single-file SMC dispatcher + services for EL3 firmware.
 * Compile with: -ffreestanding -mcpu=cortex-a72
 * 
 * Features:
 *  - Dispatcher supports multiple FIDs
 *  - Secure argument validation (TEE region)
 *  - Shared secure buffer for forwarding
 *  - Built-in echo and math services
 *  - External service registration & synchronous forwarding
 *  - Default initialization
 */

#include <stdint.h>
#include <stddef.h>

/* Memory map (from head.S) */
#define TEE_BASE        0x00000000ULL
#define TEE_SIZE        0x100000000ULL
#define NS_BASE         0x100000000ULL
#define NS_SIZE         0x100000000ULL
#define PERIPH_BASE     0xFE000000ULL
#define PERIPH_SIZE     0x02000000ULL

/* Return codes */
#define SMC_OK                  0
#define SMC_ERR_UNKNOWN_FID    ((uint64_t)-1)
#define SMC_ERR_INVALID_ARGS   ((uint64_t)-2)
#define SMC_ERR_INTERNAL       ((uint64_t)-3)
#define SMC_ERR_BUSY           ((uint64_t)-4)

/* Example FIDs */
#define FID_ECHO         0x84000001ULL
#define FID_MATH         0x84000002ULL
#define FID_FORWARD_EXT  0x84000003ULL

/* Service function type */
typedef int (*smc_service_t)(
    uint64_t arg0,uint64_t arg1,uint64_t arg2,uint64_t arg3,
    uint64_t arg4,uint64_t arg5,uint64_t arg6,uint64_t arg7,
    uint64_t *ret0,uint64_t *ret1,uint64_t *ret2,uint64_t *ret3
);

/* Simple spinlock (single-core/demo-safe) */
static volatile uint32_t spin_lock_val = 0;
static inline void spin_lock(volatile uint32_t *lock) {
    while (__atomic_test_and_set(lock,__ATOMIC_ACQUIRE)) {}
}
static inline void spin_unlock(volatile uint32_t *lock) {
    __atomic_clear(lock,__ATOMIC_RELEASE);
}

/* Shared secure buffer for forwarding */
#define SHARED_BUF_ADDR  (TEE_BASE + 0x00100000ULL)
#define SHARED_BUF_SIZE  0x1000

struct smc_shared_cmd {
    uint32_t magic;
    uint32_t version;
    uint64_t fid;
    uint64_t args[8];
    uint64_t status;
    uint64_t results[4];
    uint8_t reserved[64];
};

#define SMC_SHM_MAGIC 0x534D4353ULL /* 'SMCS' */
static struct smc_shared_cmd * const shared_cmd = (struct smc_shared_cmd *)SHARED_BUF_ADDR;

/* External service pointer */
static smc_service_t external_service_handler = NULL;
void register_external_service(smc_service_t fn) {
    external_service_handler = fn;
}

/* --- Helpers --- */
static inline int is_valid_tee_range(uint64_t addr,uint64_t size) {
    if(size==0)return 0;
    if(addr<TEE_BASE)return 0;
    uint64_t end=addr+size;
    if(end<addr)return 0;
    if(end>(TEE_BASE+TEE_SIZE))return 0;
    return 1;
}

static inline void cache_clean_range(void *addr,size_t len){(void)addr;(void)len;}
static inline void cache_invalidate_range(void *addr,size_t len){(void)addr;(void)len;}

/* --- Local services --- */
static int svc_echo(
    uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3,
    uint64_t a4,uint64_t a5,uint64_t a6,uint64_t a7,
    uint64_t *r0,uint64_t *r1,uint64_t *r2,uint64_t *r3
){
    if(!r0||!r1||!r2||!r3)return SMC_ERR_INTERNAL;
    *r0=SMC_OK; *r1=a0; *r2=a1; *r3=a2;
    return 0;
}

static int svc_math(
    uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3,
    uint64_t a4,uint64_t a5,uint64_t a6,uint64_t a7,
    uint64_t *r0,uint64_t *r1,uint64_t *r2,uint64_t *r3
){
    if(!r0||!r1||!r2||!r3)return SMC_ERR_INTERNAL;
    *r2=0;*r3=0;
    switch(a1){
        case 0: *r1=a2+a3+a4+a5; *r0=SMC_OK; return 0;
        case 1: *r1=a2*a3;       *r0=SMC_OK; return 0;
        case 2: *r1=a2^a3^a4^a5; *r0=SMC_OK; return 0;
        default: *r0=SMC_ERR_INVALID_ARGS; return SMC_ERR_INVALID_ARGS;
    }
}

/* Forwarding service */
static int svc_forward_external(
    uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3,
    uint64_t a4,uint64_t a5,uint64_t a6,uint64_t a7,
    uint64_t *r0,uint64_t *r1,uint64_t *r2,uint64_t *r3
){
    if(!r0||!r1||!r2||!r3)return SMC_ERR_INTERNAL;
    spin_lock(&spin_lock_val);
    if(!is_valid_tee_range((uint64_t)shared_cmd,sizeof(*shared_cmd))){
        spin_unlock(&spin_lock_val);*r0=SMC_ERR_INTERNAL;return SMC_ERR_INTERNAL;
    }
    shared_cmd->magic=SMC_SHM_MAGIC; shared_cmd->version=1;
    shared_cmd->fid=a0;
    shared_cmd->args[0]=a0; shared_cmd->args[1]=a1; shared_cmd->args[2]=a2; shared_cmd->args[3]=a3;
    shared_cmd->args[4]=a4; shared_cmd->args[5]=a5; shared_cmd->args[6]=a6; shared_cmd->args[7]=a7;
    cache_clean_range(shared_cmd,sizeof(*shared_cmd));
    if(!external_service_handler){
        spin_unlock(&spin_lock_val);*r0=SMC_ERR_INTERNAL;return SMC_ERR_INTERNAL;
    }
    int rc = external_service_handler(
        shared_cmd->fid, shared_cmd->args[1], shared_cmd->args[2], shared_cmd->args[3],
        shared_cmd->args[4], shared_cmd->args[5], shared_cmd->args[6], shared_cmd->args[7],
        &shared_cmd->status,&shared_cmd->results[0],&shared_cmd->results[1],&shared_cmd->results[2]
    );
    cache_invalidate_range(shared_cmd,sizeof(*shared_cmd));
    *r0=shared_cmd->status;
    *r1=shared_cmd->results[0];
    *r2=shared_cmd->results[1];
    *r3=shared_cmd->results[2];
    spin_unlock(&spin_lock_val);
    (void)rc; return 0;
}

/* Registry */
struct smc_entry {uint64_t fid; smc_service_t fn; const char *name;};
static const struct smc_entry registry[]={
    {FID_ECHO,svc_echo,"echo"},
    {FID_MATH,svc_math,"math"},
    {FID_FORWARD_EXT,svc_forward_external,"forward_external"},
};
static const unsigned registry_count=sizeof(registry)/sizeof(registry[0]);

/* External-visible handler (main.c calls this) */
void smc_handler(
    uint64_t arg0,uint64_t arg1,uint64_t arg2,uint64_t arg3,
    uint64_t arg4,uint64_t arg5,uint64_t arg6,uint64_t arg7,
    uint64_t *ret0,uint64_t *ret1,uint64_t *ret2,uint64_t *ret3
){
    if(!ret0||!ret1||!ret2||!ret3)return;
    *ret0=SMC_ERR_UNKNOWN_FID; *ret1=0; *ret2=0; *ret3=0;
    for(unsigned i=0;i<registry_count;i++){
        if(registry[i].fid==arg0){
            int rc=registry[i].fn(arg0,arg1,arg2,arg3,arg4,arg5,arg6,arg7,
                                  ret0,ret1,ret2,ret3);
            if(rc==0&&*ret0==0)*ret0=SMC_OK;
            else if(rc!=0)*ret0=(uint64_t)rc;
            return;
        }
    }
}

/* Default external service example */
static int example_external_service(
    uint64_t fid,uint64_t subcmd,uint64_t p2,uint64_t p3,
    uint64_t p4,uint64_t p5,uint64_t p6,uint64_t p7,
    uint64_t *status,uint64_t *r1,uint64_t *r2,uint64_t *r3
){
    if(!status||!r1||!r2||!r3)return SMC_ERR_INTERNAL;
    if(subcmd==0x10){*r1=p2+p3+p4; *r2=p5; *r3=p6; *status=SMC_OK; return 0;}
    *status=SMC_ERR_INVALID_ARGS; return SMC_ERR_INVALID_ARGS;
}

/* Init function to call from EL3 startup */
void smc_services_init(void){
    if(is_valid_tee_range((uint64_t)shared_cmd,sizeof(*shared_cmd))){
        shared_cmd->magic=SMC_SHM_MAGIC; shared_cmd->version=1; shared_cmd->fid=0;
        shared_cmd->status=SMC_ERR_INTERNAL; for(int i=0;i<4;i++)shared_cmd->results[i]=0;
        cache_clean_range(shared_cmd,sizeof(*shared_cmd));
    }
    register_external_service(example_external_service);
}