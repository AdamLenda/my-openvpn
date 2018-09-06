# Create your own VPN server on AWS

## Perquisites

- Must have an AWS account
- Must have already generated an AWS EC2 SSH Key Pair
- Must know how to use `SSH` to remote into an AWS EC2 instance so you can generate client credentials 
- Must know how to use `SCP` to securely copy the client credentials from the server to the client machine
- Must have already installed OpenVPN on the client machine (no configuration should be required)  

## Phase 1: Run the CloudFormation template

##### 1) Download the `my-openvpn.yml` file from this repository.

##### 2) Log into your aws console and open the CloudFormation page.

- Click "Create Stack"

##### 3) On the Create Stack page

- Choose "Upload a template to Amazon S3" and select the `my-openvpn.yml` file

- Click "Next"

##### 4) On the Specify Details page

- Set a Stack name

    This can be anything you want. Personally I use `my-openvpn`
     
    Note that the stack template will then tag all of the resources it creates with a variation of this value.
    As an example, the EC2 instance will be tagged with key pair `name="my-openvpn-server"`
    
- Select an Instance Type

    This selects the EC-2 instance size. [AWS instance size and pricing information](https://aws.amazon.com/ec2/pricing/on-demand/)

    More information available in the Notes section below

- SSH Key Pair

    Select an SSH Key Pair you've previously generated. [AWS documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html)
    
- Your Public IP Address

    This single IP will be granted the ability to SSH into the OpenVpn Server.
    
    You should only have to ssh into the server to generate new client credentials.
    
    If your IP changes, you can update this value by directly modifying the VPC Security Group `{stack-name}-public-ssh`
    
- Click "Next"

##### 5) On the Options Screen

- Click "Next"

##### 6) On the Review Screen

- On this screen, acknowledge that IAM roles will be created

- Click "Create"

##### 7) Wait for the stack status to reach `CREATE_COMPLETE`

- You can select the checkbox for the stack then use the `events` tab to monitor its progress

- Once the stack status reaches `CREATE_COMPLETE` click on the Resources tab, then click the link next to "OpenVpnServer" this will take you the details page for your OpenVPN server

## Phase 2: Creating client.opvn file

Starting from the end of phase 1

##### 1) Verify the Status your EC2 instance

- Once the EC2 instance has finished booting up, installing the needed software, and initializing OpenVPN, the `Status Checks` column should read `2/2 checks passed`

##### 2) Find the EC2 instance Public Ip

- Select the EC2 instance in the grid, then look at the details below. There should be a line similar to `IPv4 Public IP: XXX.XXX.XXX.XXX`

- The part to the right of the colon is the automatically assigned public IP of this server. Copy that value to your clip board

##### 3) SSH into your EC2 Instance

- Use whatever means is comfortable for you, but personally I use one of the following

```
> ssh-add ~/my-aws-key-pair-file
> ssh -A ec2-user@xxx.xxx.xxx.xxx
or
> ssh -i ~/my-aws-key-pair-file ec2-user@xxx.xxx.xxx.xxx
```   

- At this point you should be connected. If not see [AWS documentation on connecting to an EC2 instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstances.html).

##### 4) Generate a client certificate

- Run the following command

    ```
    > sudo my-openvpn-key-maker --new-client unique_client_name
    ``` 

    Note that the `unique_client_name` can be any string you like so long as it has not been used before

- The command output should end with something similar to:

    ```
    Client Certificate Generated: /home/ec2-user/unique_client_name.ovpn
    ```
    
- Now change the owner ship of that file

    ```
    > sudo chown ec2-user:ec2-user /home/ec2-user/unique_client_name.ovpn
    ```
    
##### You are now ready to down load your client credentials

## Phase 3 Downloading client credentials

- Open a terminal window

- Run the following command

    ```
    > scp -i ~/my-aws-key-pair-file ec2-user@xxx.xxx.xxx.xxx:~/unique_client_name.ovpn ~/unique_client_name.ovpn
    ```  

## Phase 4 Connect to your VPN

##### Run the following command

```
> sudo -i;
> openvpn --config ~/unique_client_name.ovpn --remote xxx.xxx.xxx.xxx
```
    
Note that xxx.xxx.xxx.xxx should be replaced with the same public IP address you used to SSH into your EC2 instance. 

##### Verify your connection

Open this [link](https://www.google.com/search?q=my+ip) and you should see a different IP address than before you began.

## Notes
 
### Instance Capacity

In my experience, a t3.nano has no problems running a VPN for my 130 mega-bit connection.

If you want to allow multiple users to connect to your instance, you'll need to figure out what works for you
        

### Expense

As of 2018-09 a t3.nano in US-EAST-2 costs $0.0052 per hour. This works great if your turning the VPN on and off as you need it.

In my experience, most VPN solutions cost between $40 and $50 a year. So if you use a t3.nano spot instance and
leave it on year round, you won't save much.

        US-EAST-2 t3.nano
        $0.0052 per hour * 365 days * 24 a day = $45.55 a year 


### If you reserve an instance, ~$17 a year
 
If you want to run the OpenVPN all the time you can purchase a reserved instance. You can find out more about this by
looking at [AWS reserved instance pricing.](https://aws.amazon.com/ec2/pricing/reserved-instances/)

As of 2018-09, a t3.nano in US-EAST-2 can be *_pre-paid for three years for $51_*. So that's about 1/3 the price of a
the usual VPN services provider.
    
    