# AGENTS.md

This repo is a way to virtualize ai assisted development into containers so that agents can run autonomously without much user intervention. It requires multiple mounts to make this happen well. 

The dockerfile is mostly agentic-base.dockerfile as that's the only dockerflie in repo right now

## Rules

- Ensure that changes to dockerfile are in step with the README.md documentation and the devcontainer.json files so there aren't large discrepancies in each
- Devcontainer files are compact and easy to skim and port as needed to projects, README owns explainations. Avoid verbose or needless comments in devcontainer json files
- Do not use git commit or push, user will handle this for you