# AGENTS.md

This repo is a way to virtualize ai assisted development into containers so that agents can run autonomously without much user intervention. It requires multiple mounts to make this happen well. 

The main docker file is agentic-base.dockerfile and the repo is based around that

isoai is a helper script to accomplish similar behavior to devcontainers without the specific devcontainers steps. 

## Rules

- Ensure that changes to dockerfile are in step with the [README](README.md) documentation and the devcontainer.json files so there aren't large discrepancies in each
- Devcontainer files are compact and easy to skim and port as needed to projects, [README](README.md) owns explainations. Avoid verbose or needless comments in devcontainer json files.