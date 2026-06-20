# Qlik Replicate — Minimal Docker Image (Amazon Linux 2023)

This repository builds a minimal, production‑ready Docker image for running Qlik Replicate 2026.x on Amazon Linux 2023.
It is designed for two primary use cases:

1. Local development using Docker
2. AWS Fargate deployment using the exact same image

This project is a work in progress.
Right now, it is primarily geared toward **Docker‑based development and testing**, with ECS/Fargate support evolving over time.
Future ECS‑focused enhancements will include **AWS Secrets Manager integration** to ensure sensitive values such as endpoint passwords, master key passwords, and other credentials are never exposed in environment variables or task definitions.

This image is also intended to be used as a base image for downstream Dockerfiles that need to add endpoint drivers or custom integrations.
By keeping this image minimal, clean, and secure, it provides a stable foundation for building more specialised Replicate containers.

---

## Why is this minimal?

This project intentionally focuses on minimalism and determinism:

- Only the packages required for Replicate to run are installed
- No systemd or init system
- No unnecessary utilities or debugging tools
- No endpoint drivers bundled by default
- Clean, predictable build layers
- Pinned base image digest for reproducibility

A minimal image is smaller, more secure, faster to deploy, and easier to maintain.
It provides a clean foundation that downstream Dockerfiles can extend with endpoint drivers or additional tooling.

---

## Why Amazon Linux 2023?

Qlik’s official example uses CentOS 8, which is now end‑of‑life and receives no security updates.
This makes it unsuitable for production workloads and causes vulnerability scanners to flag the image immediately.

Amazon Linux 2023 provides:

- Active security patching
- A hardened, minimal base
- Long‑term support
- A modern glibc toolchain
- Better compatibility with AWS services
- A smaller attack surface
- No systemd by default, making it ideal for containers

For AWS Fargate, Amazon Linux 2023 is the natural, secure, and future‑proof choice.

---

## Security posture and vulnerability profile

This project is designed with security as a first‑class concern:

- Base image pinned by digest to prevent supply‑chain drift
- Amazon Linux 2023 provides continuous CVE patching
- Minimal dependency footprint reduces attack surface
- No systemd, cron, SSH, or unnecessary daemons
- No legacy CentOS packages
- No outdated libraries
- No embedded drivers that may introduce vulnerabilities

Compared to Qlik’s CentOS‑based example, this image:

- Has dramatically fewer CVEs
- Passes vulnerability scans more cleanly
- Is suitable for regulated environments
- Aligns with AWS security best practices

This makes it a strong foundation for production deployments and downstream custom builds.

---

## Features

- Amazon Linux 2023 base image pinned by digest for reproducibility
- Silent, non‑systemd installation of Qlik Replicate 2026.5.0
- Minimal runtime dependencies only
- Custom entrypoint script that:
  - Creates the Replicate data directory
  - Sets the admin password
  - Imports a license if provided
  - Starts the Replicate service on the configured port
  - Dynamically tails all active log files
  - Watches for new log files using inotify
  - Keeps the container alive indefinitely
- Fully compatible with AWS Fargate
- Includes official Qlik example files for reference
- Designed to be used as a base image for adding endpoint drivers
- ECS‑ready design, with future support for AWS Secrets Manager

---

## Build Instructions

Clone the repository:

git clone https://github.com/VegyBS/qlik-replicate-docker
cd qlik-replicate-docker

Build the image:

docker build -t qlik-replicate:latest .

Force rebuild of the installer layer:

docker build --build-arg CACHE_BUST=$(date +%s) -t qlik-replicate:latest .

---

## Running Locally (Development Mode)

docker run \
  -p 3563:3563 \
  -e ReplicateDataFolder=/data \
  -e ReplicateAdminPassword=admin \
  -e ReplicateRestPort=3563 \
  -e ReplicateLicense="$(base64 -w0 license.txt)" \
  qlik-replicate:latest

Then open the Replicate UI:

http://localhost:3563

---

## Running with Docker Compose

services:

  replicate:
    image: qlik-replicate:latest
    build:
      context: .
      dockerfile: ./qlik-replicate/Dockerfile
    container_name: replicate
    ports:
      - "3562:3562"
    environment:
      ReplicateDataFolder: /replicate/data
      ReplicateAdminPassword: SomeLongPassword1
      ReplicateRestPort: 3562
    volumes:
       - replicate-data:/replicate/data

volumes:
  replicate-data:

networks:
  default:
    name: replicate-network

Start the environment:

docker compose up --build

Open the UI:

http://localhost:3562

Stop the environment:

docker compose down

Reset all data:

docker compose down -v

---

## Running on AWS Fargate (Production Mode)

This image is designed to run as‑is on Fargate.

Recommended configuration:

- Store the license in AWS Secrets Manager
- Mount persistent storage (EFS) for /data
- Pass admin password via task environment variables
- Expose the configured REST port in the task definition

Future versions of this project will include:

- Native AWS Secrets Manager integration
- Secure retrieval of endpoint passwords
- Secure retrieval of master key passwords
- Removal of all sensitive values from environment variables

Example task definition snippet:

{
  "image": "your-ecr-repo/qlik-replicate:latest",
  "essential": true,
  "portMappings": [
    { "containerPort": 3563, "protocol": "tcp" }
  ],
  "environment": [
    { "name": "ReplicateDataFolder", "value": "/data" },
    { "name": "ReplicateAdminPassword", "value": "..." },
    { "name": "ReplicateRestPort", "value": "3563" }
  ]
}

---

## Environment Variables

ReplicateDataFolder
Path where Replicate stores its data and logs. Must be writable.

ReplicateAdminPassword
Password for the Replicate UI.

ReplicateRestPort
REST API and UI port. Default is 3563.

ReplicateLicense
Optional. May be provided as a plain file path or as base64 text.
If provided, it will be imported on startup.

---

## How the Entrypoint Works

The entrypoint script performs the following steps:

1. Validates that ReplicateDataFolder, ReplicateAdminPassword, and ReplicateRestPort are set.
2. Creates the data directory if it does not exist and assigns ownership to the attunity user.
3. Sets the Replicate admin password using repctl.
4. Imports a license if ReplicateLicense is provided.
5. Starts the Replicate service on the configured port.
6. Tails all existing log files in the data directory.
7. Watches the log directory for new log files using inotify and tails them automatically.
8. Keeps the container alive by waiting on background tail processes.

This makes the container suitable for both local debugging and long‑running production workloads.

---

## Differences from Qlik’s Official Example

This repository includes Qlik’s official qlik-docker-example folder for reference, but the build in this repository intentionally diverges from Qlik’s example in several important ways.

### Uses Amazon Linux 2023 instead of CentOS 8
Qlik’s example uses CentOS 8, which is end‑of‑life and full of unpatched vulnerabilities.
This project uses Amazon Linux 2023, which is actively maintained, hardened, and secure.

### Minimal, container‑native build
Qlik’s example includes extra utilities and a heavier base image.
This project installs only what Replicate needs, resulting in a smaller, more secure image.

### Production‑oriented entrypoint
Qlik’s example is designed for demonstration.
This project’s entrypoint is designed for real workloads, including password setup, license import, log tailing, and long‑running stability.

### Clean data separation
This project enforces a dedicated ReplicateDataFolder and persistent volume, aligning with container best practices.

### Designed as a base image
This project is intentionally structured so that downstream Dockerfiles can extend it with endpoint drivers or custom integrations.

In short:
Qlik’s example shows how Replicate can run in Docker.
This repository shows how Replicate should run in production.

---

## Roadmap for Endpoint Driver Support

Future enhancements planned for this repository include:

- Optional installation of common endpoint drivers
- Modular driver installation system
- Ability to mount drivers at runtime
- Documentation for driver‑specific dependencies
- Automated validation of installed drivers
- Optional multi‑stage builds for driver‑heavy configurations
- Example downstream Dockerfiles showing how to extend this base image
- AWS Secrets Manager integration for secure credential retrieval

The goal is to keep the base image minimal while providing a clean, extensible path for adding endpoint support when needed.

---

## What This Project Cannot Provide (Legal and Licensing Boundaries)

This repository focuses on containerisation, automation, and operational best practices for Qlik Replicate.
However, there are strict legal boundaries around what can and cannot be included:

### This project cannot provide:
- Qlik Replicate binaries
- Qlik Replicate licenses
- Endpoint drivers that are licensed or distributed by Qlik
- Any proprietary Qlik content not publicly available
- Any mechanism to bypass licensing or activation

### This project can provide:
- A minimal, secure, production‑ready container foundation
- Examples of how to structure downstream Dockerfiles
- Guidance on how to integrate your own licensed drivers
- Operational best practices for running Replicate in Docker and Fargate

### Important licensing note
Qlik Replicate licenses are only available directly from Qlik or an authorised Qlik partner.
They cannot be generated, downloaded, or obtained from this repository.
You must supply your own valid license file when running the container.

---

## qlik-docker-example (Official Qlik Examples)

The qlik-docker-example folder contains the official example files provided by Qlik.
These are included for reference only and are not used directly by this minimal build.

They demonstrate Qlik’s intended container workflow, but this repository provides a more modern, secure, and production‑oriented alternative.

---

## Official Qlik Resources

Qlik Replicate Documentation
https://help.qlik.com/en-US/replicate/May2026/Content/Replicate/Main/Introduction/Home.htm

Qlik Replicate Community Forums
https://community.qlik.com/t5/Qlik-Replicate/bd-p/qlik-replicate-discussions

---

## Repository Structure

./docker
./docker/docker-compose.yml
./docker/qlik-replicate
./docker/qlik-replicate/Dockerfile
./docker/qlik-replicate/scripts
./qlik-docker-example
./qlik-docker-example/start_replicate.sh
./qlik-docker-example/README.md
./qlik-docker-example/README
./qlik-docker-example/run_docker.sh
./qlik-docker-example/db2client.rsp
./qlik-docker-example/drivers
./qlik-docker-example/create-dockerfile.sh
./README.md
./LICENSE
./.gitignore

---

## About the Author

This project is maintained by an engineer with nearly three decades of experience working with data and databases, around fifteen years in ETL and ELT, and more than six years supporting and building Qlik Replicate in containerised environments using Docker, AWS Fargate, and CI/CD automation.

The intention behind this repository is not to claim authority, but to share practical experience and create a foundation others can build on.
The best solutions come from collaboration, and contributions, suggestions, and improvements from the community are genuinely welcome.

---

## Troubleshooting

Replicate UI not loading:
- Ensure the correct port is exposed
- Check container logs for missing dependencies

License rejected:
- Qlik Replicate licenses are only available directly from Qlik or an authorised Qlik partner
- They cannot be generated, downloaded, or obtained from this repository
- The license file may be supplied as a plain file or as base64 text
- Ensure the license matches the installed Replicate version

Installer fails on Amazon Linux 2023:
- Ensure the RPM filename matches the version in the Dockerfile
- AL2023 requires non‑systemd installation

---

## License

This project is MIT licensed.
Qlik Replicate is a commercial product and requires a valid license.
