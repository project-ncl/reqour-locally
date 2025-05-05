# Reqour Locally

Wanna run [Reqour](https://github.com/project-ncl/reqour) locally?

Then this repository is exactly for you!!

## Reqour REST and Adjuster

Reqour consists of the 2 main components:
- **reqour-rest**
  - contains endpoint handler implementations
  - handles all the requests itself (e.g. `POST /internal-scm`), but `POST /adjust`
  - when alignment request comes, reqour-rest only creates spawns a new reqour-adjuster pod, properly configures it, and newly created adjuster pod executes all the remaining stuff (e.g. running a manipulator process inside of it)
- **reqour-adjuster**
  - CLI app which executes the whole alignment process

---

- for more info about how Reqour works, see [its README](https://github.com/project-ncl/reqour/blob/main/README.md)
- this repository helps with running locally **both reqour-rest and reqour-adjuster**

## How it runs locally?
- local run is executed through an OCI Runtime, e.g. Podman

### Why OCI container, and not just `quarkus dev`?
- reqour-rest could be easily run as `quarkus dev`, but running reqour-adjuster locally would require tools to run alignment in the host OS (e.g. several versions of Gradle), which would significantly complicate the process, since anyone who wishes to run reqour locally would need to intsall and maintain several versions of these tools
- because of the above, OCI container approach is used, which requires only OCI Runtime and compose tool (e.g. docker compose) to successfully run both reqour-rest and reqour-adjuster
- **Note:** since there is a need to run reqour-adjuster using OCI Runtime, in order to make it consistent, this approach is used for reqour-rest as well

## Build & Deploy
- prior to running an OCI Image (hence, creating an OCI Container), we need to build the image
- this repository helps with both building an image, and also running the image afterward

## Repository Structure

- `adjuster/`
  - `build/`
    - `build.sh`
      - build script for building the image
    - `build-args.conf`
      - build arguments required during building of the image
  - `deploy/`
    - `deploy.sh`
      - script to run the previously built image
    - `env-vars.conf`
      - environment variables required during run
    - `mounts/`
      - directories which are mount as volumes into the container
      - e.g. mount with configurations (`application.yaml`) or secrets

---
- the same holds also for reqour-rest component

- `rest`
    - `build/`
        - `build.sh`
        - `build-args.conf`
    - `deploy/`
        - `deploy.sh`
        - `env-vars.conf`
        - `mounts/`

---
- finally, common functions reused between both components are placed under `common/`:

- `common/`
  - `library.sh`
    - library with general functions
  - `build-library.sh`
    - library with build-related functions
  - `deploy-library.sh`
    - library with deploy-related functions
  - `todos-hunter.sh`
    - script which searches for TODOs, which are to be replaced by real values
  - `volume-importer.sh`
    - handles importing of a directory into a volume

## Workflow
- this section describes the way you should use this repository in order to successfully build & deploy reqour-rest / reqour-adjuster
- for the sake of simplicity, **this description will describe only reqour-rest**, but the workflow for reqour-adjuster is the same, so it should not be a problem for you to replicate the same steps and successfully obtain build & deployment of reqour-adjuster

### Build Part
- self-explanatory way on how to build is to look at `build.sh`'s help:

```shell
$ ./build.sh -h                                       

Usage: ./build.sh [OPTIONS] [ -- ] ARGUMENTS

OPTIONS:
  -h, --help              Show this help usage
  -v, --verbose           Verbose output
  -r, --oci-runtime       OCI runtime to be used to build the image. Defaults to 'podman'.
  -t, --image-tag         Image tag of the built image. Defaults to 'reqour-rest'.
  -a, --build-args-file   Build Arguments file (with relative path to context direcotry). Defaults to 'build-args.conf'.
  -b, --build-dir         Build Directory containing e.g. Build Arguments file. Defaults to '/tmp/reqour/rest/build'.

ARGUMENTS:
  1                       Context directory for the build
```

- we can see that it requires a single argument, the build context (directory with reqour-rest's Containerfile), hence, an example run could be:

```shell
$ ./build.sh -v ~/repos/pnc-mpp/reqour-image
/tmp/reqour/rest/build/build-args.conf: REQOUR_URL=TODO # Paste Reqour URL, e.g. that one of the latest successful build at Jenkins
###############################################################
# Paste correct values for all the TODOs, and then try again! #
###############################################################
```

- we get an error, which is expected when run the first time, since what happens is that [build-args.conf](rest/build/build-args.conf) inside this repository is copied locally into some repository at your OS (by default, it is: `/tmp/reqour/rest/build`, as help shows)
- and since this contains the following TODO:
```
REQOUR_URL=TODO # Paste Reqour URL, e.g. that one of the latest successful build at Jenkins
```
you have to provide the correct value, and only then you will be able to continue
- **❗Note:** you do change this value inside the generated file in `--build-dir` (by default, `/tmp/reqour/rest/build`), **NOT** in the `build-args.conf` located in this repository, this has 2 reasons:
  1) files in this repository are just templates, they are not used by OCI Runtime during build, those in `--build-dir` are
  2) you do not want to provide real values in this repository, since you are risking the change of unintentionally commit these values, which is definitely unwanted and introduces a security vulnerability
 
- once the value is provided, you re-run the script again, your image should be successfully built (by default, it will be tagged `localhost/reqour-rest:latest`), so feel free to double-check e.g. by running:
```shell
podman images | grep reqour-rest
```

### Deploy Part
- self-explanatory way on how to deploy is to look at `deploy.sh`'s help:

```shell
$ ./deploy.sh -h

Usage: ./build.sh [OPTIONS] [ -- ] COMMAND

OPTIONS:
  -h, --help              Show this help usage
  -v, --verbose           Verbose output
  -b, --compose-backend   Backend for compose. Defaults to 'docker compose'.
  -t, --image-tag         Image tag of the built image. Defaults to 'reqour-rest'.
  -c, --container-name    Container name. Defaults to 'reqour-rest'.
  -p, --port              Port (at host) where to bind the container port. Defaults to '8080'.
  -m, --detach            Run compose up in detached mode. Defaults to true.
  -d, --deploy-dir        Deployment directory containing all the necessary resources, e.g. compose.yaml. Defaults to '/tmp/reqour/rest/deploy'.
  -e, --env-filename      Environment variables filename within the deploy directory. Defaults to 'env-vars.conf'.
  -r, --oci-runtime       OCI Runtime used when creating new volumes used by reqour-rest. Defaults to 'podman'.

COMMAND:
  template PROFILE        Create a template (with TODOs to be changed) for the given profile.
  import-volumes          Import all the needed deployment resources into volumes (creates the volumes if not exist).
  up                      Create compose file and run the container.
  down                    Stop the container, delete the compose file.

PROFILE:
  devel                   Development environment
  stage                   Stage environment
  prod                    Prod environment
```

- we can see that the possible commands are:
  - `template devel | stage | prod`, e.g. `template devel`
  - `import-volumes`
  - `up`
  - `down`
- these commands are run then in chronological order from up to down, i.e., at first you run `template PROFILE`, then `import-volumes`, and finally `up`
- let's see the commands in action to understand it even better

### Command `template PROFILE`
- like `build.sh`, based on the files within `/deploy`, creates copies of files within `--deploy-dir` (by default, `/tmp/reqour/rest/deploy`)
- so let's say we run:
```shell
./deploy.sh template devel
```
- we should end up with:
```shell
$ tree /tmp/reqour/rest/deploy 
/tmp/reqour/rest/deploy
├── env-vars.conf
└── mounts
    ├── configurations
    │   └── application.yaml
    └── secrets
        ├── kafka-client-truststore-devel
        │   └── kafka_jaas_conf
        └── reqour-devel
            ├── gitlab-sa-token
            ├── pnc-bot-ssh
            └── pnc-reqour-sa-secret
```

- instead of TODOs in the newly generated files, provide real values, and continue with the `import-volumes` command

- **❗Note 1:** like with build, we do change generated files, **NOT** the files present in this repository
- **Note 2:** since we ran the command with the `devel` profile, some directories are suffixed `-devel`
- **Note 3:** it is sufficient to run this command once per each environment

### Command `import-volumes`
- until we do not provide a value for every TODO, `./deploy.sh import-volumes` will **not** work, and will end up with error, e.g.:
```shell
$ ./deploy.sh import-volumes
/tmp/reqour/rest/deploy/mounts/secrets/reqour-devel/pnc-reqour-sa-secret: TODO -- Reqour SA secret
/tmp/reqour/rest/deploy/mounts/configurations/application.yaml: # TODO -- Configure everything, i.e., just copy & paste the correct application.yaml
###############################################################
# Paste correct values for all the TODOs, and then try again! #
###############################################################
```
- once we configure everything, `./deploy.sh import-volumes` should succeed
- the result of this command is:
  - all the required volumes are created (if not already exist)
  - corresponding content from `--deploy-dir` is imported into corresponding volumes
- finally, in case the import was successful, we are able to finally run the container

**Note:** it is enough to run this command only when we have changed something in `--deploy-dir` and we want to propagate this change into successive container runs

### Command `up`
- creates the compose file in the `--deploy-dir`, and then runs `docker compose up -d` (by default, you can override it using the `--compose-backend` or `--detach` options)
  - you can see the content of the compose file when using the `--verbose` flag

#### Adjuster's Command `up`
- here the only difference which needs to be done compared to adjuster: when executing the `up` command, you need to also specify the following environment variables:
  - `BUILD_TYPE`
    - [build type](https://github.com/project-ncl/pnc-api/blob/master/src/main/java/org/jboss/pnc/api/enums/BuildType.java), valid values are: `MVN`, `GRADLE`, `NPM`, or `SBT`
  - `ADJUST_REQUEST`
    - [adjust request](https://github.com/project-ncl/pnc-api/blob/master/src/main/java/org/jboss/pnc/api/reqour/dto/AdjustRequest.java) in JSON format as defined in PNC API

### Command `down`
- stops and removes the container
