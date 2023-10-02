# k3sraspbian

This is a derivative of: https://github.com/k3s-io/k3s-ansible

This has been completely modified to leverage 64-bit Raspberry Pi OS as opposed to 32 bit Raspbian.

In order to use, you must modify: https://github.com/nethrose/k3sraspbian/blob/48ccda0f4304777010568ac392e14a849873173b/ansible.cfg#L2

...and point to the appropriate location for your cfg file. I need to make that a variable sometime soon, probs. Though I doubt anyone is using this outside of myself.
