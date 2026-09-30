#!/bin/bash

cd "$(dirname "$0")"

# Create folder structure
mkdir -p RedisClient/App
mkdir -p RedisClient/Views/{Sidebar,Connection,KeyBrowser,ValueEditors,CommandExecutor,PubSub,Monitoring,Settings,Common,Modifiers}
mkdir -p RedisClient/ViewModels
mkdir -p RedisClient/Models
mkdir -p RedisClient/Services
mkdir -p RedisClient/Network/RESPProtocol
mkdir -p RedisClient/Utilities/{Extensions,Formatters,Validators,Logging,Constants}
mkdir -p RedisClient/Resources/{Styles}
mkdir -p RedisClientTests/{Network,Services,ViewModels,Utilities,Fixtures}

# Create .gitkeep files
find . -type d -empty -exec touch {}/.gitkeep \;

echo "✓ Project structure created"
