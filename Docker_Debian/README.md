##Debian-based docker image

First, build pgator as usual in its directory.

Then:
```bash
$ cp bin/pgator Docker_Debian/
$ sudo docker build -t pgator Docker_Debian/
```
This builds a pgator docker image.
