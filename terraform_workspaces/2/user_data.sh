#!/bin/bash

# Export user-specific environment variables
export git_username="${git_username}"
export git_token="${git_token}"
export git_repo="${git_repo}"
export git_branch="${git_branch}"
export docker_username="${docker_username}"
export docker_token="${docker_token}"
export sonar_admin_password="admin123" # Set a secure password

# Create a directory for our setup
mkdir -p /root/playground/cicd-setup
cd /root/playground/cicd-setup

# ... [previous SonarQube setup remains the same]

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

# ... [rest of the Jenkins configuration]

# Example pipeline that uses the repository information
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