// SPDX-License-Identifier: GPL-2.0
/* Apply a DT overlay (from /lib/firmware) at module load time. */
#include <linux/module.h>
#include <linux/firmware.h>
#include <linux/of.h>
#include <linux/platform_device.h>

static char *name = "nura-display.dtbo";
module_param(name, charp, 0444);
static int ovcs_id;

static int __init nura_ovl_init(void)
{
	const struct firmware *fw;
	int ret;

	ret = request_firmware(&fw, name, NULL);
	if (ret)
		return ret;
	ret = of_overlay_fdt_apply(fw->data, fw->size, &ovcs_id, NULL);
	release_firmware(fw);
	if (ret)
		pr_err("nura-ovl: apply %s failed: %d\n", name, ret);
	else
		pr_info("nura-ovl: applied %s (id %d)\n", name, ovcs_id);
	return ret;
}
module_init(nura_ovl_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Nura DT overlay loader");
