# Local Argo stack, Crossplane and Kargo sandbox in Kind

1. Fork repo
2. Change all 'https://github.com/koorikla/argo-stack' for your repo in `helm/argo/values.yaml`
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

4. Commit any manifest to ./manifests folder and sync the app


# Crossplane

1. Create ./aws-credentials.txt
```
[default]  
aws_access_key_id = EXAMPLEACCESSKEY  
aws_secret_access_key = EXAMPLESECRET
```
2. Create secret out of the credentials
`kubectl create secret generic aws-secret --from-file=creds=./aws-credentials.txt -n crossplane-system`
3. Sync Crossplane app in ArgoCD
4. Create example manifest (for instance comment out bucket object in manifests/random-manifest.yaml)

# Kargo
1. Sync kargo application in ArgoCD
2. Create project or any object in Kargo GUI
3. Create a gitlab/github token and add it through GUI (or a k8s secret)
4. To import your Kargo components created through GUI to GitOps use kubectl ala
   1. `kubectl get projects kargo-demo -o yaml`
   2. `kubectl get stages kargo-demo -o yaml`
   3. ...
5. Commit to manifests folder