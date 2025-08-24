pipeline {
	agent {
		label 'linux-agent'
	}


    parameters {
		string(name: 'JMX_FILE', defaultValue: 'your-test.jmx', description: 'JMeter test plan file')
        string(name: 'THREADS', defaultValue: '50', description: 'Number of threads')
        string(name: 'DURATION', defaultValue: '60', description: 'Test duration in seconds')
    }

    environment {
		COMPOSE_PROJECT_NAME = "jmeter-ci-${BUILD_NUMBER}"
        TIMESTAMP = sh(script: "date +%Y%m%d_%H%M%S", returnStdout: true).trim()
        RESULTS_FILE = "results_${TIMESTAMP}.csv"
        REPORT_DIR = "report_${TIMESTAMP}"
    }

    stages {
		stage('Checkout') {
			steps {
				checkout scm
                echo "Starting JMeter performance test"
            }
        }

        stage('Start Infrastructure') {
			steps {
				sh '''
                    echo "Starting InfluxDB and Grafana..."
                    docker-compose up -d influxdb grafana

                    # Wait for InfluxDB to be ready
                    echo "Waiting for InfluxDB to start..."
                    until curl -sf http://localhost:8086/ping; do
                        echo "Waiting for InfluxDB..."
                        sleep 5
                    done
                    echo "InfluxDB is ready"

                    # Wait for Grafana
                    echo "Waiting for Grafana to start..."
                    sleep 15
                    echo "Grafana should be ready at http://localhost:3000"
                '''
            }
        }

        stage('Run JMeter Test') {
			steps {
				script {
					sh '''

                        echo "Running JMeter test..."
                        docker-compose run --rm jmeter jmeter -n \
                            -t /tests/${JMX_FILE} \
                            -l /results/${RESULTS_FILE} \
                            -e -o /results/${REPORT_DIR} \
                            -Jthreads=${THREADS} \
                            -Jduration=${DURATION}

                        # Copy results from container
                        docker cp jmeter-runner:/results ./

                        echo "JMeter test completed"
                        ls -la results/
                    '''
                }
            }
        }

        stage('Generate Summary') {
			steps {
				script {
					def summary = sh(
                        script: '''
                            if [ -f results/${RESULTS_FILE} ]; then
                                awk -F',' 'NR>1 {
                                    total++; rt+=$2;
                                    if($8=="true") errors++
                                } END {
                                    printf "Total Requests: %d\\n", total
                                    printf "Average Response Time: %.0fms\\n", rt/total
                                    printf "Error Rate: %.1f%%\\n", errors/total*100
                                }' results/${RESULTS_FILE}
                            else
                                echo "Results file not found"
                            fi
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "=== Performance Test Summary ==="
                    echo summary
                    writeFile file: "test-summary.txt", text: summary
                }
            }
        }

        stage('Publish Reports') {
			steps {
				// Publish HTML Report
                publishHTML([
                    allowMissing: false,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: "results/${env.REPORT_DIR}",
                    reportFiles: 'index.html',
                    reportName: 'JMeter Performance Report',
                    reportTitles: "Performance Test - ${env.TIMESTAMP}"
                ])

                echo "Reports published successfully"
                echo "Grafana Dashboard: http://localhost:3000 (admin/admin123)"
            }
        }
    }

    post {
		always {
			// Archive artifacts
            archiveArtifacts artifacts: 'results/**, test-summary.txt',
                           fingerprint: true,
                           allowEmptyArchive: true
        }

        success {
			echo "Performance test completed successfully"
            echo "HTML Report: ${BUILD_URL}JMeter_20Performance_20Report/"
            echo "Grafana: http://localhost:3000"
        }

        failure {
			echo "Performance test failed"
        }

        cleanup {
			// Optional: Stop containers after test
            sh 'docker-compose down || true'
        }
    }
}