#!/bin/bash

# Export user-specific environment variables
export git_username="${git_username}"
export git_token="${git_token}"
export docker_username="${docker_username}"
export docker_token="${docker_token}"
export sonar_admin_password="admin123" # Set a secure password

# Create a directory for our setup
mkdir -p /root/playground/cicd-setup
cd /root/playground/cicd-setup

# Function to wait for a service to be ready
wait_for_service() {
    local service_url=$1
    local max_attempts=30
    local attempt=1
    
    echo "Waiting for $service_url to be ready..."
    while ! curl -s -f "$service_url" >/dev/null; do
        if [ $attempt -eq $max_attempts ]; then
            echo "Service $service_url not ready after $max_attempts attempts. Exiting."
            exit 1
        fi
        echo "Attempt $attempt: Service not ready yet. Retrying in 10 seconds..."
        sleep 10
        ((attempt++))
    done
    echo "Service $service_url is ready!"
}

# Create Docker network for services
docker network create cicd-network 2>/dev/null || true

# Start SonarQube
docker run -d --name sonarqube \
    --network cicd-network \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    -p 9000:9000 \
    sonarqube:latest

# Wait for SonarQube to be ready
wait_for_service "http://localhost:9000"

# Generate SonarQube token
echo "Generating SonarQube token..."
sonar_token=$(curl -X POST -u admin:admin \
    "http://localhost:9000/api/user_tokens/generate" \
    -d "name=jenkins-token" | jq -r '.token')

# Change default admin password
curl -X POST -u admin:admin \
    "http://localhost:9000/api/users/change_password" \
    -d "login=admin&previousPassword=admin&password=${sonar_admin_password}"

# Create Jenkins Dockerfile
cat <<EOL > Dockerfile
FROM jenkins/jenkins:lts-jdk17
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
COPY jenkins.yaml /usr/share/jenkins/ref/jenkins.yaml

# Install the necessary plugins
RUN jenkins-plugin-cli --plugins \
"git:latest \
configuration-as-code \
docker-workflow \
docker-plugin \
pipeline-stage-step \
credentials-binding \
ssh-credentials \
plain-credentials \
credentials \
workflow-cps \
pipeline-groovy-lib \
sonar:latest"
EOL

# Create jenkins.yaml for Configuration as Code
cat <<EOL > jenkins.yaml
jenkins:
  systemMessage: "Jenkins configured by JCasC"
  globalNodeProperties:
    - envVars:
        env:
          - key: "SONARQUBE_URL"
            value: "http://sonarqube:9000"
          - key: "GIT_REPO"
            value: "${git_repo}"
          - key: "GIT_BRANCH"
            value: "${git_branch}"
  credentials:
    system:
      domainCredentials:
        - domain: "global"
          credentials:
            - string:
                scope: GLOBAL
                id: "git-credentials-id"
                secret: "\${git_token}"
                description: "GitHub credentials"
            - string:
                scope: GLOBAL
                id: "docker-credentials-id"
                secret: "\${docker_token}"
                description: "Docker Hub credentials"
            - string:
                scope: GLOBAL
                id: "sonarqube-token"
                secret: "${sonar_token}"
                description: "SonarQube Token"

tool:
  sonarRunnerInstallation:
    installations:
    - name: "SonarQube Scanner"
      properties:
      - installSource:
          installers:
          - sonarRunnerInstaller:
              id: "4.8.0.2856"
EOL

# Build Jenkins image
docker build -t jenkins:jcasc .

# Remove existing Jenkins container if it exists
docker rm -f jenkins 2>/dev/null || true

# Run Jenkins container
docker run --name jenkins --rm \
    --network cicd-network \
    -p 8080:8080 \
    -e GIT_USERNAME="${git_username}" \
    -e GIT_TOKEN="${git_token}" \
    -e DOCKER_USERNAME="${docker_username}" \
    -e DOCKER_TOKEN="${docker_token}" \
    jenkins:jcasc

# Print summary
echo "Setup complete!"
echo "Jenkins URL: http://localhost:8080"
echo "SonarQube URL: http://localhost:9000"
echo "SonarQube credentials: admin/${sonar_admin_password}"
echo "SonarQube token: ${sonar_token}"

# Example pipeline that can be used in Jenkins
cat <<EOL > example-pipeline.groovy
pipeline {
    agent any
    
    tools {
        sonar 'SonarQube Scanner'
    }
    
    stages {
        stage('Checkout') {
            steps {
                git branch: env.GIT_BRANCH,
                    url: env.GIT_REPO,
                    credentialsId: 'git-credentials-id'
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        sonar-scanner \
                        -Dsonar.projectKey=${GIT_REPO##*/} \
                        -Dsonar.projectName=${GIT_REPO##*/} \
                        -Dsonar.sources=. \
                        -Dsonar.host.url=${SONARQUBE_URL} \
                        -Dsonar.login=${SONAR_TOKEN}
                    '''
                }
            }
        }
    }
}
EOL
