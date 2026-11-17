# Terraform
## VMs

Each VM runs in its own segment on a libvirt network in `route` mode. There is
no NAT: the host owns the `.1` address of every segment and routes traffic
between them (`net.ipv4.ip_forward=1` must be enabled on the host).

| Segment | Network       | VM (`ip`)   | Gateway (host) |
| ------- | ------------- | ----------- | -------------- |
| web     | 10.40.1.0/24  | 10.40.1.2   | 10.40.1.1      |
| app     | 10.40.2.0/24  | 10.40.2.2   | 10.40.2.1      |
| db      | 10.40.3.0/24  | 10.40.3.2   | 10.40.3.1      |

DHCP is disabled; each VM gets a static address from `cloud-init/network-config.tftpl`
(netplan, matched by MAC). Segments are defined as data in the `segments`
variable in `main.tf`.

Commands

```
cd terraform/vm
terraform init
terraform plan
terraform apply
terraform destroy
```

After `apply`, check that forwarding works between segments:

```
ping 10.40.2.2    # from web
ping 10.40.3.2    # from web
```
