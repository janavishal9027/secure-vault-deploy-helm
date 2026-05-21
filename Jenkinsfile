// Deploy pipeline for the secure-vault-deploy-helm repo.
//
// This is the DEPLOY repo — it runs `helm upgrade --install` for the whole
// secure-vault stack. The service repos (UI, authentication, notes, roles,
// ai-core-service, ai-worker) only build + push images; this repo rolls them
// out by pinning tags/digests in image-versions/<env>_image.yaml and
// applying the Helm chart.
//
// Jenkins runs ON THE VPS (the LXD host), so it skips the rsync/ssh layer in
// ci/deploy.sh and runs ci/deploy-remote.sh directly against the local
// workspace. deploy-remote.sh tars the chart into the LXD container and runs
// `helm upgrade` inside it via `lxc exec`.
//
// ---------------------------------------------------------------------------
// Jenkins setup:
//   No credentials needed — deploy is local to the VPS.
//   The user the Jenkins process runs as must be able to run `lxc exec` /
//   `lxc file push` without a password prompt (lxd group membership).
//   `tar` must be on PATH. helm + kubectl run INSIDE the LXD container, so
//   they do not need to be installed on the host.
// ---------------------------------------------------------------------------

pipeline {
  agent any

  parameters {
    choice(
      name: 'ENV_NAME',
      choices: ['dev-a', 'dev-b', 'test', 'stage', 'prod'],
      description: 'Target environment — picks secure-vault-helmchart/envs/<ENV_NAME>/ and image-versions/<ENV_NAME>_image.yaml.'
    )
    string(
      name: 'SCOPE',
      defaultValue: 'all',
      description: "Comma-separated service names to wait on for rollout, or 'all'. The chart always renders the full set; SCOPE only narrows the rollout-status wait."
    )
    string(
      name: 'LXD_CONTAINER',
      defaultValue: '',
      description: "LXD container override. Leave blank to use the default 'secure-vault-<ENV_NAME>'."
    )
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Deploy') {
      steps {
        script {
          // Push params into env explicitly — declarative `parameters` are
          // not reliably exposed as shell env vars (and on the very first
          // build they register the job's params but run unset). deploy.sh
          // defaults LXD_CONTAINER to secure-vault-<ENV_NAME> when blank;
          // mirror that here.
          env.RESOLVED_ENV_NAME = params.ENV_NAME
          env.RESOLVED_SCOPE = params.SCOPE?.trim() ?: 'all'
          env.RESOLVED_LXD_CONTAINER = params.LXD_CONTAINER?.trim() ?: "secure-vault-${params.ENV_NAME}"
          echo "Deploying ENV_NAME=${env.RESOLVED_ENV_NAME}  LXD_CONTAINER=${env.RESOLVED_LXD_CONTAINER}  SCOPE=${env.RESOLVED_SCOPE}"
        }
        sh '''
          set -eu

          # The repo may be checked out with CRLF line endings on some
          # setups; strip them so bash doesn't choke on the script.
          sed -i 's/\\r$//' ci/deploy-remote.sh
          chmod +x ci/deploy-remote.sh

          # Jenkins is on the LXD host, so REMOTE_DIR is just the workspace.
          # deploy-remote.sh cd's into it and expects the chart +
          # image-versions layout to be present (which it is — this IS the
          # deploy repo).
          env \
            LXD_CONTAINER="$RESOLVED_LXD_CONTAINER" \
            ENV_NAME="$RESOLVED_ENV_NAME" \
            SCOPE="$RESOLVED_SCOPE" \
            REMOTE_DIR="$WORKSPACE" \
            bash ci/deploy-remote.sh
        '''
      }
    }
  }

  post {
    always {
      // deploy-remote.sh tees a per-run log into $WORKSPACE/logs — keep it
      // as a build artifact before the workspace is cleaned.
      archiveArtifacts artifacts: 'logs/*.log', allowEmptyArchive: true
    }
    success {
      echo "Deploy complete: ${params.ENV_NAME} (scope=${params.SCOPE})"
    }
  }
}
