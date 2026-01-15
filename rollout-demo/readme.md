# Demo with nginx-ingress and argo-rollouts
Todo: istio

1. Sync https://argocd.local/applications/argo/rollout-demo?conditions=false&resource=&view=tree

2. Open http://rollouts-demo.local and http://argo-rollouts.local/rollouts/rollout/default/rollouts-demo

3. Change image version in rollout from blue to green via https://argocd.local/applications/argo/rollout-demo?conditions=false&resource=&view=tree , check network tab in argocd

4. http://rollouts-demo.local notice you see granulally increasing number of green dots

5. Promote in argo-rollouts dashboard http://argo-rollouts.local/rollouts/rollout/default/rollouts-demo, all dots should display green in the demo app
