Docker container for testing
============================

The folder contains scripts and configs for isolated project building and testing using [Docker](https://www.docker.com/).

1. [Install docker](http://docs.docker.com/linux/step_one/)
2. [Install docker-compose](https://docs.docker.com/compose/install/)
3. Run:

```
docker-compose build
docker-compose up
```

Notes
=====

1. Note that dub dependencies are cached in folder `dub-cache`. Delete it if you want to start a clean build.
2. For repeating tests the second command should be modified to:

```
docker-compose up --force-recreate
```

3. You can manually enter the container and test by hands:

```
docker-compose build
docker-compose run pgator bash
```