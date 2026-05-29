pipeline {
    agent none

    options {
        timestamps()
    }

    stages {
        stage('General Agent') {
            agent { label 'linux && arm64 && general' }
            steps {
                sh '''
                    echo "NODE_NAME=$NODE_NAME"
                    hostname
                    whoami
                    java -version
                    git --version
                    jq --version
                '''
            }
        }

        stage('ALM Agent') {
            agent { label 'linux && arm64 && alm' }
            steps {
                sh '''
                    echo "NODE_NAME=$NODE_NAME"
                    curl --version
                    jq --version
                '''
            }
        }

        stage('Docker Agent') {
            agent { label 'linux && arm64 && docker' }
            steps {
                sh '''
                    echo "NODE_NAME=$NODE_NAME"
                    docker version
                    docker compose version
                    docker buildx version
                '''
            }
        }
    }
}