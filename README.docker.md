# Docker

Get started with SigScale's CAMEL Service Environment (CSE) running in a Docker container image:
```
$ docker pull sigscale/cse
$ docker run -ti --entrypoint bash -h host1 -v db:/home/otp/db sigscale/cse
otp@host1:~$ bin/initialize
otp@host1:~$ exit
$ docker run -ti -h host1 -v db:/home/otp/db -p 8080:8080/tcp -p 3868:3868/tcp sigscale/ocs
```

## Support
Contact <support@sigscale.com> for further assistance.

