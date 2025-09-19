# Visual Architecture Diagrams

## System Overview

```ascii
┌─────────────────────────────────────────────────────────────────┐
│                    Machine Rites Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   User      │    │   System    │    │  External   │         │
│  │ Interface   │◄──►│   Core      │◄──►│ Services    │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│         │                   │                   │              │
│         ▼                   ▼                   ▼              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Bootstrap  │    │   Config    │    │   GitHub    │         │
│  │   Script    │    │ Management  │    │     API     │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│         │                   │                   │              │
│         ▼                   ▼                   ▼              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Shell      │    │   Chezmoi   │    │   Package   │         │
│  │ Libraries   │    │ Templates   │    │ Managers    │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Component Interaction Flow

```ascii
Bootstrap Process Flow:
┌────────────┐
│   Start    │
└──────┬─────┘
       ▼
┌────────────┐     ┌─────────────┐
│ Parse Args │────►│ Pre-flight  │
└────────────┘     │   Checks    │
                   └──────┬──────┘
                          ▼
                   ┌─────────────┐
                   │   Backup    │
                   │  Existing   │
                   └──────┬──────┘
                          ▼
    ┌─────────────────────┴─────────────────────┐
    ▼                     ▼                     ▼
┌──────────┐      ┌──────────────┐      ┌─────────────┐
│   SSH    │      │     GPG      │      │   System    │
│  Setup   │      │   & Pass     │      │ Dependencies│
└────┬─────┘      └──────┬───────┘      └──────┬──────┘
     ▼                   ▼                     ▼
┌──────────┐      ┌──────────────┐      ┌─────────────┐
│ Generate │      │  Initialize  │      │   Install   │
│   Keys   │      │    Store     │      │   Missing   │
└────┬─────┘      └──────┬───────┘      └──────┬──────┘
     └──────────────────┬──────────────────────┘
                        ▼
                 ┌─────────────┐
                 │   Chezmoi   │
                 │ Initialize  │
                 └──────┬──────┘
                        ▼
                 ┌─────────────┐
                 │    Apply    │
                 │ Templates   │
                 └──────┬──────┘
                        ▼
                 ┌─────────────┐
                 │    Tool     │
                 │ Installation│
                 └──────┬──────┘
                        ▼
                 ┌─────────────┐
                 │ Verification│
                 │  & Health   │
                 └─────────────┘
```

## Module Dependency Graph

```ascii
Library Dependencies:
┌─────────────────────────────────────────────────────────────────┐
│                        lib/common.sh                            │
│                    (Core utilities)                             │
└─────────────┬───────────────────────────────┬─────────────────┘
              ▼                               ▼
    ┌─────────────────┐                ┌─────────────────┐
    │  lib/atomic.sh  │                │lib/validation.sh│
    │ (File operations│                │ (Input checking)│
    └─────────────────┘                └─────────────────┘
              ▼                               ▼
    ┌─────────────────┐                ┌─────────────────┐
    │ lib/platform.sh │                │ lib/testing.sh  │
    │ (OS detection)  │                │(Test framework) │
    └─────────────────┘                └─────────────────┘
              │                               │
              └───────────────┬───────────────┘
                              ▼
                    ┌─────────────────┐
                    │bootstrap_machine│
                    │   _rites.sh     │
                    │ (Main script)   │
                    └─────────────────┘
```

## Configuration System Architecture

```ascii
Configuration Layers:
┌─────────────────────────────────────────────────────────────────┐
│                      User Layer                                 │
│  ~/.bashrc.d/99-local.sh (Local overrides, gitignored)         │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Template Layer                                │
│  .chezmoi/dot_bashrc.d/*.tmpl (Templated configurations)       │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Core Layer                                   │
│  ~/.bashrc.d/ (Generated configurations)                       │
│  ├── 00-hygiene.sh      (Shell options)                        │
│  ├── 10-bash-completion.sh (Completions)                       │
│  ├── 30-secrets.sh      (Secret management)                    │
│  ├── 35-ssh.sh          (SSH agent)                            │
│  ├── 40-tools.sh        (Development tools)                    │
│  ├── 50-prompt.sh       (Shell prompt)                         │
│  └── 60-aliases.sh      (Aliases and functions)                │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    System Layer                                 │
│  /etc/bash.bashrc, /etc/profile (System defaults)              │
└─────────────────────────────────────────────────────────────────┘
```

## Security Architecture

```ascii
Security Layers:
┌─────────────────────────────────────────────────────────────────┐
│                   Application Layer                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │Environment  │  │    Scripts  │  │    Config   │             │
│  │ Variables   │  │ Validation  │  │ Validation  │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Encryption Layer                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │     GPG     │  │    Pass     │  │     SSH     │             │
│  │   Keys      │  │   Store     │  │    Keys     │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   File System Layer                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Permissions │  │   Atomic    │  │   Backup    │             │
│  │    0600     │  │ Operations  │  │ & Restore   │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

## Tool Integration Map

```ascii
Development Tools Integration:
                    ┌─────────────────┐
                    │   ~/.bashrc     │
                    │  (Main loader)  │
                    └────────┬────────┘
                             ▼
             ┌───────────────────────────────┐
             │       ~/.bashrc.d/            │
             │   (Modular configuration)     │
             └────────┬──────────────────────┘
                      ▼
     ┌────────────────┼────────────────┐
     ▼                ▼                ▼
┌─────────┐    ┌─────────────┐    ┌─────────┐
│   NVM   │    │   Python    │    │  Rust   │
│ Node.js │    │   & PyEnv   │    │ Cargo   │
└────┬────┘    └──────┬──────┘    └────┬────┘
     ▼                ▼                ▼
┌─────────┐    ┌─────────────┐    ┌─────────┐
│   NPM   │    │     PIP     │    │ Rustup  │
│  Yarn   │    │ Pipenv, etc │    │   etc   │
└─────────┘    └─────────────┘    └─────────┘

Container & Cloud Tools:
┌─────────┐    ┌─────────────┐    ┌─────────┐
│ Docker  │    │ Kubernetes  │    │   AWS   │
│ Podman  │    │   kubectl   │    │   CLI   │
└────┬────┘    └──────┬──────┘    └────┬────┘
     └────────────────┼────────────────┘
                      ▼
              ┌─────────────┐
              │   Shell     │
              │Completions  │
              └─────────────┘
```

## Data Flow Diagram

```ascii
Configuration Data Flow:
┌─────────────┐
│   Git Repo  │
│ (Templates) │
└──────┬──────┘
       ▼
┌─────────────┐    ┌─────────────┐
│   Chezmoi   │───►│ Template    │
│   Engine    │    │ Processing  │
└─────────────┘    └──────┬──────┘
       ▲                  ▼
       │           ┌─────────────┐
       │           │  Generated  │
       │           │    Files    │
       │           └──────┬──────┘
       │                  ▼
┌─────────────┐    ┌─────────────┐
│  User Data  │    │   Target    │
│ Detection   │    │ File System │
│(git config) │    │(~/.bashrc.d)│
└─────────────┘    └─────────────┘

Secret Management Flow:
┌─────────────┐
│ Plaintext   │
│ Secrets     │
│(deprecated) │
└──────┬──────┘
       ▼
┌─────────────┐    ┌─────────────┐
│ Migration   │───►│     GPG     │
│   Script    │    │ Encryption  │
└─────────────┘    └──────┬──────┘
                          ▼
                   ┌─────────────┐
                   │    Pass     │
                   │    Store    │
                   └──────┬──────┘
                          ▼
                   ┌─────────────┐
                   │Environment  │
                   │ Variables   │
                   └─────────────┘
```

## State Machine Diagram

```ascii
Bootstrap State Machine:
     ┌─────────────┐
     │    INIT     │
     └──────┬──────┘
            ▼
     ┌─────────────┐
     │ VALIDATING  │◄────────────┐
     └──────┬──────┘             │
            ▼                    │
     ┌─────────────┐             │
     │  BACKING_UP │             │
     └──────┬──────┘             │
            ▼                    │
     ┌─────────────┐             │
     │ INSTALLING  │             │
     └──────┬──────┘             │
            ▼                    │
     ┌─────────────┐        ┌────┴────┐
     │CONFIGURING  │───────►│  ERROR  │
     └──────┬──────┘        └────┬────┘
            ▼                    │
     ┌─────────────┐             │
     │ VERIFYING   │             │
     └──────┬──────┘             │
            ▼                    │
     ┌─────────────┐             │
     │  COMPLETE   │             │
     └─────────────┘             │
                                 ▼
                          ┌─────────────┐
                          │  ROLLBACK   │
                          └─────────────┘
```

## Performance Optimization Map

```ascii
Performance Optimization Points:
┌─────────────────────────────────────────────────────────────────┐
│                    Shell Startup Time                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Fast Path (< 100ms):                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Basic ENV  │───►│    PATH     │───►│   Aliases   │         │
│  │  Variables  │    │   Setup     │    │ & Functions │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│                                                                 │
│  Lazy Loading (on demand):                                     │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │     NVM     │    │   PyEnv     │    │   Docker    │         │
│  │  (Node.js)  │    │  (Python)   │    │Completions  │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│        │                  │                  │                │
│        └──────────────────┼──────────────────┘                │
│                           ▼                                   │
│                   ┌─────────────┐                             │
│                   │   Cached    │                             │
│                   │ Detection   │                             │
│                   └─────────────┘                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Error Handling Architecture

```ascii
Error Handling Layers:
┌─────────────────────────────────────────────────────────────────┐
│                    User Interface                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Clear     │  │Actionable   │  │   Progress  │             │
│  │ Messages    │  │ Guidance    │  │  Reporting  │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Recovery Mechanisms                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  Automatic  │  │   Manual    │  │  Graceful   │             │
│  │  Rollback   │  │   Restore   │  │ Degradation │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Logging & Tracking                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Error     │  │  Operation  │  │    Debug    │             │
│  │    Logs     │  │   Traces    │  │   Context   │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

These visual diagrams provide a comprehensive overview of the machine-rites architecture, showing how different components interact, data flows through the system, and how various concerns are handled.