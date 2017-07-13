# AWS
#### Just a random collection of scripts/tools for use in AWS
---
### EC2
###### ec2_admin.pl
* Work in progress
* Displays Regions and Availability Zones
* Displays info on all non-terminated instances in a given region
* User needs to export/specify AWS key/secret and region to work with
* See help for more info

* Sample Output for AMI listing
```
  [ami-12345678]
     Owner:                     083091234567
     Name:                      Ubuntu 16.04
     Description:               Ubuntu 16.04
     State:                     available
     Image Type:                machine
     Architecture:              x86_64
     Virtualization:            hvm
     Hypervisor:                xen
     Root Device Type:          ebs
     Public:                    False
     Tags:
                       Name: Ubuntu 16.04 04-25-2017
```
* Sample Output for Region Listing
```
 [us-east-1]
     Endpoint:         ec2.us-east-1.amazonaws.com
     Zones:
                       us-east-1a
                       us-east-1b
                       us-east-1c
                       us-east-1d
                       us-east-1e
                       us-east-1f
     VPCs:
                       vpc-1234567e
                            Name: My VPC
                            CIDR Block: 172.230.32.0/19
                            Tenancy: default
                            State: available

     AMIs:
                       ami-12345678
                            Description: Ubuntu 16.04
                            Architecture: x86_64
                            Virtualization: hvm
                            Root Device Type: ebs
                            Tags:
                                Name: Ubuntu 16.04 04-25-2017
```

* Sample Instance Output
```
 [i-1b2b6n7t]
     Hostname                   my.host.net
     Instance Type:             m3.large
     Zone:                      eu-central-1a
     VPC:                       vpc-123456tb (My VPC)
     Subnet:                    subnet-a3674944
     Reservation:               r-12345abc
     Image ID:                  ami-12345678
     Private IP:                172.230.32.30
     Public IP:                 82.19.30.88
     Private Name:              ip-172-230-32-30.eu-central-1.compute.internal
     Public Name:               ec2-82-19-30-88.eu-central-1.compute.amazonaws.com
     Launch Time:               2015-12-03T20:26:41.000Z
     State:                     running
     IAM Role:                  MyIamRole
     Volumes:
                       /dev/sda1
                            ID: vol-1b23b8f2
                            Type: gp2
                            Delete on Termination: True
                            Size: 16 GB
                            IOPS: 100
                            Snap: snap-8312abc6
                            Zone: eu-central-1a
                            Status: in-use
                            Created: 2015-12-03T20:26:45.239Z
                            Encrypted: False

     User Data:
                       my-data1=foo
                       my-data2=bar
                       my-data3=lorem ipsum

     Tags:
                       Name: my.host.net
                       OS: Ubuntu

     Security Groups:
                       mySG-1
                            ID: sg-abc1234d
                            Ingress Rules:
                                tcp from: 22 to: 22
                                     Source IP: 198.168.0.1/32
                            Egress Rules:
```

---
### S3
###### s3_admin.pl
* Work in progress
* Displays S3 Buckets and contents
* User needs to export/specify AWS key/secret for authentication
* See help for more info

