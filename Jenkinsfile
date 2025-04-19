@Library('Shared')_

pipeline {
    agent { 
        label 'dev-server' 
    }
    
    environment {
        // Consolidated environment variables
        DOCKER_IMAGE        = "geminiamit"
        GIT_REPO           = "https://github.com/Amitabh-DevOps/dev-gemini-clone.git"
        GIT_BRANCH         = "DevOps"
        DOCKERHUB_CREDS    = credentials('dockerhub-creds')  // Use Jenkins credentials
        DOCKER_IMAGE_NAME  = "${DOCKERHUB_CREDS_USR}/${DOCKER_IMAGE}"
        NODE_VERSION       = "18"                            // Explicit version pinning
        TRIVY_SEVERITY     = "CRITICAL,HIGH"                 // Security scan threshold
    }

    parameters {
        string(name: 'GEMINI_DOCKER_TAG', defaultValue: 'v1-${BUILD_NUMBER}', description: 'Auto-incremented tag with build number')
    }

    options {
        timeout(time: 30, unit: 'MINUTES')                   // Fail if stuck
        buildDiscarder(logRotator(numToKeepStr: '10'))       // Clean old builds
        disableConcurrentBuilds()                            // Avoid race conditions
    }

    stages {
        stage("Clean Workspace") {
            steps {
                cleanWs()
                // Free disk space aggressively
                sh 'docker system prune -af --volumes || true'
            }
        }

        stage("Code Checkout") {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "${GIT_BRANCH}"]],
                    extensions: [
                        // Shallow clone for faster checkout
                        [$class: 'CloneOption', depth: 1, shallow: true],
                        // Clean after checkout
                        [$class: 'CleanBeforeCheckout']
                    ],
                    userRemoteConfigs: [[
                        url: "${GIT_REPO}",
                        // Use SSH credentials for security
                        credentialsId: 'github-ssh-key'
                    ]]
                ])
            }
        }

        stage("Build & Test") {
            parallel {
                stage("Build Docker Image") {
                    steps {
                        script {
                            // Multi-arch build support
                            docker.build(
                                "${DOCKER_IMAGE_NAME}:${params.GEMINI_DOCKER_TAG}",
                                "--build-arg NODE_VERSION=${NODE_VERSION} ."
                            )
                        }
                    }
                }
                stage("Unit Tests") {
                    steps {
                        sh 'npm test'
                        junit '**/test-results.xml'  // Publish test results
                    }
                }
            }
        }

        stage("Security Scans") {
            parallel {
                stage("SonarQube Analysis") {
                    steps {
                        withSonarQubeEnv('Sonar') {
                            sh """
                            sonar-scanner \
                                -Dsonar.projectKey=${DOCKER_IMAGE} \
                                -Dsonar.sources=. \
                                -Dsonar.exclusions=node_modules/**
                            """
                        }
                    }
                }
                stage("Trivy Scan") {
                    steps {
                        sh """
                        trivy image --exit-code 1 \
                            --severity ${TRIVY_SEVERITY} \
                            --ignore-unfixed \
                            --format sarif \
                            --output trivy-results.sarif \
                            ${DOCKER_IMAGE_NAME}:${params.GEMINI_DOCKER_TAG}
                        """
                        archiveArtifacts 'trivy-results.sarif'
                    }
                }
                stage("Dependency Check") {
                    steps {
                        dependencyCheckAnalyzer(
                            datadir: '',
                            hintsFile: '',
                            includeVulnReports: true,
                            odcInstallation: 'OWASP',
                            scanSet: '**/*.*',
                            skipOnScmChange: false,
                            skipOnUpstreamChange: false
                        )
                        dependencyCheckPublisher(
                            pattern: '**/dependency-check-report.xml'
                        )
                    }
                }
            }
        }

        stage("Quality Gate") {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage("Push to Registry") {
            steps {
                script {
                    docker.withRegistry('https://registry.hub.docker.com', 'dockerhub-creds') {
                        docker.image("${DOCKER_IMAGE_NAME}:${params.GEMINI_DOCKER_TAG}").push()
                        // Tag as latest for stable deployments
                        docker.image("${DOCKER_IMAGE_NAME}:${params.GEMINI_DOCKER_TAG}").push('latest')
                    }
                }
            }
        }
    }

    post {
        always {
            // Always clean up
            sh 'docker system prune -af || true'
            script {
                currentBuild.description = "Tag: ${params.GEMINI_DOCKER_TAG}"
            }
        }
        success {
            build job: "Gemini-CD", 
                  parameters: [string(name: 'GEMINI_DOCKER_TAG', value: "${params.GEMINI_DOCKER_TAG}")],
                  wait: false  // Async trigger
            // Enhanced notification
            slackSend(
                color: 'good',
                message: """✅ SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}
                            | Image: ${DOCKER_IMAGE_NAME}:${params.GEMINI_DOCKER_TAG}
                            | Branch: ${GIT_BRANCH}
                            | Details: ${env.BUILD_URL}"""
            )
        }
        failure {
            // Critical failures alert
            slackSend(
                color: 'danger',
                channel: '#alerts',
                message: """🚨 FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}
                            | Error: ${currentBuild.currentResult}
                            | Console: ${env.BUILD_URL}console"""
            )
        }
        unstable {
            // Test failures alert
            emailext body: "Unit tests failed in ${env.BUILD_URL}testReport",
                     subject: "UNSTABLE: ${env.JOB_NAME}",
                     to: 'qa-team@example.com'
        }
    }
}