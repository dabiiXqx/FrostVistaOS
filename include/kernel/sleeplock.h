#ifndef __KERNEL_SLEEPLOCK_H__
#define __KERNEL_SLEEPLOCK_H__

#include "kernel/spinlock.h"

struct sleeplock {
	int locked;
	struct spinlock lock;
	// struct spinlock {
	// 	uint locked;
	// 	char *name;
	// 	struct cpu *cpu;
	// };

	char *name;
	int pid;
};

#endif
