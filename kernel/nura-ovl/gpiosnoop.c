// SPDX-License-Identifier: GPL-2.0
/* Nura: count transitions on TLMM GPIO pads (reads GPIO_IN directly) */
#include <linux/module.h>
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/delay.h>

static unsigned long base = 0x0f100000;
module_param(base, ulong, 0444);

static int __init gs_init(void)
{
	void __iomem *tlmm = ioremap(base, 0x200000);
	static const int pins[] = { 15, 16, 17, 18 };
	int p;

	if (!tlmm)
		return -ENOMEM;

	for (p = 0; p < ARRAY_SIZE(pins); p++) {
		void __iomem *in = tlmm + 0x1000 * pins[p] + 0x4;
		unsigned int last = readl_relaxed(in) & 1, cur;
		int i, trans = 0, ones = 0;
		ktime_t t0 = ktime_get();

		for (i = 0; i < 200000; i++) {
			cur = readl_relaxed(in) & 1;
			ones += cur;
			if (cur != last)
				trans++;
			last = cur;
		}
		pr_info("gpiosnoop: gpio%d: transitions=%d ones=%d/200000 in %lld us (cfg=0x%x)\n",
			pins[p], trans, ones, ktime_to_us(ktime_sub(ktime_get(), t0)),
			readl_relaxed(tlmm + 0x1000 * pins[p]));
	}
	iounmap(tlmm);
	return -EAGAIN;	/* do not stay loaded */
}
module_init(gs_init);
MODULE_LICENSE("GPL");
