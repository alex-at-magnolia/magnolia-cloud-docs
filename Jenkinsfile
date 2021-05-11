 pipeline {

    options {
        ansiColor('xterm')
    }

    agent {
        label 'docker'
    }

    environment {
        AWS_REGION      = "eu-central-1"
        TF_CLI_ARGS     = "-input=false"
        PRODUCTION_S3_BUCKET  = "docs.beta.de.magnolia-cloud.com"
        OKTA_API_TOKEN   = credentials('okta/api_token')
    }

    stages {
        stage('Verify changes') {
            when {
                beforeAgent true
                anyOf {
                    branch 'master'
                    changeRequest()
                }
            }

            agent {
                docker {
                    image "magnolia-cloud-terragrunt:$env.STB_VERSION"
                    registryUrl "https://${env.REGISTRY_BASE_URL}"
                    registryCredentialsId "${env.REGISTRY_CREDENTIALS_ID}"
                    label "docker"
                    reuseNode true
                    alwaysPull true
                    args '-u root:root --entrypoint=\'\''
                }
            }

            steps {
                script {
                    withAWS(region: "${env.AWS_REGION}", credentials: "${env.MAGNOLIA_CLOUD_STAGING_CREDENTIALS_ID}") {
                        dir('infra/') {
                            sh "aws iam get-user"
                            sh "terraform init -reconfigure -backend-config='bucket=magnolia-internal-docs-infra-tfstate'"
                            sh "terraform plan -var-file=prod.tfvars"
                        }
                    }
                }
            }
        }

        // NOTE: linting is part of UI bundle build already
        stage('Build UI bundle') {
            when {
                beforeAgent true
                anyOf {
                    branch 'master'
                    changeRequest()
                }
            }

            agent {
                docker {
                    image "node:10.22.1-alpine3.9"
                    label "docker"
                    reuseNode true
                    alwaysPull true
                    args '-u root:root --entrypoint=\'\''
                }
            }
        // For testing use same docker image above. and try the commands to get output.... 

            steps {
                echo 'Building UI bundle ...'
                dir('ui/') {
                    sh 'apk add build-base libtool automake autoconf nasm zlib'
                    sh 'rm -rf build'
                    sh 'npm install'
                    sh 'npm install gulp-cli'
                    sh './node_modules/.bin/gulp bundle'
                }
            }
        }


        stage('Build Antora site') {
            when {
                beforeAgent true
                anyOf {
                    branch 'master'
                    changeRequest()
                }
            }

            agent {
                docker {
                    image "antora/antora:2.3.4"
                    label "docker"
                    reuseNode true
                    alwaysPull true
                }
            }

            steps {
                withCredentials([string(credentialsId: 'BITBUCKET_ACCESS_TOKEN', variable: 'BITBUCKET_ACCESS_TOKEN')]) {
                    sh "echo https://sre.robot:${BITBUCKET_ACCESS_TOKEN}@git.magnolia-cms.com >> ~/.git-credentials"
                    echo 'Building Antora documentation ...'
                    sh 'npm install'
                    sh 'rm -rf build/site'
                    sh 'npm install'
                    withCredentials([usernamePassword(credentialsId: 'NEXUS_CREDENTIALS', usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
                      sh 'antora generate --fetch playbook.yml'
                    }
                }
            }
        }

        stage('Deploy Infra in Production') {
            when {
                beforeAgent true
                branch 'master'
            }

            agent {
                docker {
                    image "magnolia-cloud-terragrunt:$env.STB_VERSION"
                    registryUrl "https://${env.REGISTRY_BASE_URL}"
                    registryCredentialsId "${env.REGISTRY_CREDENTIALS_ID}"
                    label "docker"
                    reuseNode true
                    alwaysPull true
                    args '-u root:root --entrypoint=\'\''
                }
            }

            steps {
                withAWS(region: "${env.AWS_REGION}", credentials: "${env.MAGNOLIA_CLOUD_STAGING_CREDENTIALS_ID}") {
                    dir('infra/') {
                        sh "terraform init -reconfigure -backend-config='bucket=magnolia-internal-docs-infra-tfstate'"
                        sh "terraform apply -var-file=prod.tfvars -auto-approve"
                    }
                }
            }
        }

        stage('Deploy Antora site to S3 in Production') {
            when {
                beforeAgent true
                branch 'master'
            }

            agent {
                docker {
                    image "magnolia-cloud-terragrunt:$env.STB_VERSION"
                    registryUrl "https://${env.REGISTRY_BASE_URL}"
                    registryCredentialsId "${env.REGISTRY_CREDENTIALS_ID}"
                    label "docker"
                    reuseNode true
                    alwaysPull true
                    args '-u root:root --entrypoint=\'\''
                }
            }

            steps {
                withAWS(region: "${env.AWS_REGION}", credentials: "${env.MAGNOLIA_CLOUD_STAGING_CREDENTIALS_ID}") {
                    sh "aws s3 cp build/site/ s3://${env.PRODUCTION_S3_BUCKET}/ --recursive"
                    sh "aws s3 sync build/site/ s3://${env.PRODUCTION_S3_BUCKET}/ --delete"
                }
            }
        }
    }
}

def setBuildName() {
    currentBuild.displayName = "${env.BUILD_NUMBER}-prod"
}
