pipeline {
	agent {
		label 'linux-agent'
	}

    parameters {
		string(name: 'JMX_FILE', defaultValue: 'FakeAPIStore-Test-Plan.jmx', description: 'JMeter test plan file')
        string(name: 'THREADS', defaultValue: '5', description: 'Number of threads')
        string(name: 'DURATION', defaultValue: '20', description: 'Test duration in seconds')
    }

    environment {
		COMPOSE_PROJECT_NAME = "jmeter-ci-${BUILD_NUMBER}"
        TIMESTAMP = sh(script: "date +%Y%m%d_%H%M%S", returnStdout: true).trim()
        RESULTS_FILE = "detailed-results_${TIMESTAMP}.csv"
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
                    until curl -sf http://localhost:8087/ping; do
                        echo "Waiting for InfluxDB..."
                        sleep 5
                    done
                    echo "InfluxDB is ready"

                    # Wait for Grafana
                    echo "Waiting for Grafana to start..."
                    sleep 15
                    echo "Grafana should be ready at http://localhost:3001"
                '''
            }
        }

        stage('Debug - Check Paths') {
			steps {

				sh '''
            		echo "=== Current working directory ==="
            		pwd

            		echo "=== Directory contents ==="
            		ls -la

            		echo "=== test-plans folder contents ==="
            		ls -la test-plans/ || echo "test-plans folder not found"

            		echo "=== Full path being used ==="
            		echo "Looking for: $(pwd)/test-plans/${JMX_FILE}"

            		echo "=== Check if file exists --> Okay? ==="
            		test -f "test-plans/${JMX_FILE}" && echo "File exists" || echo "File NOT found"
        		'''
    		}
		}


        stage('Run JMeter Test') {
			steps {
				script {
					sh '''
                		echo "Running JMeter test with ${THREADS} users..."

                		# Ensure JMeter is available
                		which jmeter || export PATH=/opt/apache-jmeter/bin:$PATH

                		# Create results directory
                		mkdir -p results

                		# Run JMeter test
                			jmeter -n \
                            -t test-plans/${JMX_FILE} \
    						-l test-data/${RESULTS_FILE} \
    						-q user.properties \
    						-e -o results/${REPORT_DIR} \
    						-Jthreads=${THREADS} \
    						-Jrampup=${RAMP_UP} \
    						-Jduration=${DURATION}

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
                            if [ -f test-data/${RESULTS_FILE} ]; then
                                awk -F',' 'NR>1 {
                                    total++; rt+=$2;
                                    if($8=="true") errors++
                                } END {
                                    printf "Total Requests: %d\\n", total
                                    printf "Average Response Time: %.0fms\\n", rt/total
                                    printf "Error Rate: %.1f%%\\n", errors/total*100
                                }' test-data/${RESULTS_FILE}
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
				slackSend(
    color: 'good', // green
    message: """
			✅ *BUILD SUCCESS*
				*Job:* ${env.JOB_NAME}
				*Build:* #${env.BUILD_NUMBER}
				*Status:* SUCCESS
				*Triggered By:* ${currentBuild.getBuildCauses()[0].shortDescription}
				echo "Performance test completed successfully"
            	echo "HTML Report: ${BUILD_URL}JMeter_20Performance_20Report/"
            	echo "Grafana: http://localhost:3001"
    		"""
				)
			}

        failure {
			slackSend(
    			color: 'danger', // red
    			message: """
						❌ *BUILD FAILED*
							*Job:* ${env.JOB_NAME}
							*Build:* #${env.BUILD_NUMBER}
							*Status:* FAILED
							*Triggered By:* ${currentBuild.getBuildCauses()[0].shortDescription}
							echo "Performance test failed"
    					"""
			)
		}

        cleanup {
			// Optional: Stop containers after test
            sh 'docker-compose down || true'
        }
    }
}