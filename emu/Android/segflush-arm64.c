/*
 * ARM64 cache flush for Android
 * Uses __builtin___clear_cache for Android compatibility
 *
 * CRITICAL FIX for Android 10+ ARM64:
 * On Android 10 and later with ARM64, JIT-compiled code cannot execute
 * from memory that only has PROT_READ|PROT_WRITE permissions.
 *
 * We use mprotect to add PROT_EXEC to the memory region.
 */

#include <sys/types.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <android/log.h>

#include "dat.h"

/* Define page size if not available */
#ifndef PAGESIZE
#define PAGESIZE 4096
#endif

#define TAG "TaijiOS-segflush"

/* Check for MAP_JIT support (Android 10+) */
#ifndef MAP_JIT
#define MAP_JIT 0x800
#endif

/*
 * segflush: flush instruction cache for ARM64 on Android
 * Also makes the memory executable for JIT code
 */
int
segflush(void *a, ulong n)
{
	static int call_count = 0;

	if(n != 0) {
		long page_size = sysconf(_SC_PAGESIZE);
		if(page_size <= 0)
			page_size = PAGESIZE;

		/* Align start address down to page boundary */
		uintptr_t start = (uintptr_t)a & ~(page_size - 1);
		/* Align end address up to page boundary */
		uintptr_t end = ((uintptr_t)a + n + page_size - 1) & ~(page_size - 1);
		size_t len = end - start;

		/* Log calls for debugging */
		if(call_count < 20) {
			__android_log_print(ANDROID_LOG_INFO, TAG,
				"segflush: call %d, a=%p, n=%lu, start=%p, len=%zu",
				call_count, a, n, (void*)start, len);
			call_count++;
		}

		/* Try to make memory executable */
		if(mprotect((void*)start, len, PROT_READ|PROT_WRITE|PROT_EXEC) != 0) {
			__android_log_print(ANDROID_LOG_ERROR, TAG,
				"segflush: mprotect FAILED for %p+%zu: errno=%d",
				(void*)start, len, errno);
		} else {
			if(call_count <= 20) {
				__android_log_print(ANDROID_LOG_INFO, TAG,
					"segflush: mprotect succeeded for %p+%zu",
					(void*)start, len);
			}
		}

		/* Clear instruction cache */
		__builtin___clear_cache((char*)a, (char*)a + n);
	}
	return 0;
}
