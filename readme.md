spesifikasi 
os:
ubuntu server 22.04.5 LTS
link: [download](https://ubuntu.com/download/server/thank-you?version=22.04.5&architecture=amd64&lts=true)
ukuran file: 1.98 GB (2,136,926,208 bytes)

cara cek storage
df -h

cara cek memory
free -h

ubah dulu ke Network mode bridge

```bash
chmod +x snortEnv.sh
sudo ./snortEnv.sh
```


after instalation
dway@dway:~/snort$ free -h
               total        used        free      shared  buff/cache   available
Mem:            10Gi       6.4Gi       154Mi       4.0Mi       3.6Gi       3.4Gi
Swap:             0B          0B          0B
dway@dway:~/snort$ df -h
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           1.1G  1.2M  1.1G   1% /run
/dev/sda2        62G   18G   42G  30% /
tmpfs           5.1G  512K  5.1G   1% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           1.1G  4.0K  1.1G   1% /run/user/1000
dway@dway:~/snort$