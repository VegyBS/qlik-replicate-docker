# Qlik Containerization Documentation

This folder contains the script files necessary to make a Dockerfile that can be built and used to run Qlik Replicate in a containerized environment.

## Scripts Overview

- **create-dockerfile.sh**:
  - This script automates the creation of a Dockerfile based on the drivers specified in `drivers`.

- **drivers**:
  - Contains key-value pairs describing which drivers to install and their corresponding installation files.

- **db2client.rsp**:
  - The response file for IBM DB2 for LUW client installation.

- **README**
  - The original Qlik created readme document.

- **README.md**:
  - This document.

- **run_docker.sh**:
  - Script to run the Docker image after it's built. Accepts parameters such as the REST port, Docker image name, Replicate password, data folder, and container name.

- **start_replicate.sh**:
  - Internal script used by the created Dockerfile to run Replicate.

## Usage

### Building the Docker Image

1. **Create a `drivers` file** with the required format:
    ```
    oracle21.8        = oracle-instantclient-basiclite-21.8.0.0.0-1.el8.x86_64.rpm
    sqlserver18.1     = msodbcsql18-18.1.2.1-1.x86_64.rpm
    mysql8            = mysql-connector-odbc-8.0.32-1.el8.x86_64.rpm
    db2luw11.1        = DB2_ESE_AUSI_Svr_11.1_Linux_86-64.tar.gz
    ```

2. **Run the build script**:
    ```bash
    ./create-dockerfile.sh
    mv temp_dockerfile Dockerfile
    docker build -t my-custom-replicate .
    ```

### Running the Docker Container

1. **Run the container with the required parameters**:
    ```bash
    ./run_docker.sh <REST_port> <Docker_image_name> <Replicate_password> [<Data_folder>] [<Container_name>]
    ```

## Notes

- Ensure that all necessary RPM and tar.gz files are available in the Docker context folder.
- Customize environment variables in `create-dockerfile.sh` as needed to suit your specific requirements.
- For persistence, consider using Docker volumes or bind mounts for the Replicate data folder.

For detailed usage instructions and examples, refer to the provided scripts and documentation.