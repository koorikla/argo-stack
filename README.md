# Local Argo stack

1. Fork repo
2. Change all 'https://github.com/koorikla/argo-stack' for your repo in helm/argo/values.yaml
   1. `sed -i '' 's|https://github.com/koorikla/argo-stack|https://github.com/yourRepo/argo-stack|g' helm/argo/values.yaml`

3. Run the script in docker / podman to spin up your local cluster and add Argo stack to it
 
# OSX
```bash
brew install --cask docker
open -a Docker
brew install helm kind kubectl
chmod +x script.sh
sudo ./script.sh
```
