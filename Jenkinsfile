pipeline {
	agent {
		label 'linux-agent'
	}

    parameters {
		string(name: 'JMX_FILE', defaultValue: 'FakeAPIStore-Test-Plan.jmx', description: 'JMeter test plan file')
        string(name: 'THREADS', defaultValue: '50', description: 'Number of threads')
        string(name: 'DURATION', defaultValue: '20', description: 'Test duration in seconds')
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
    						-l results/${RESULTS_FILE} \
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
                echo "Grafana Dashboard: http://localhost:3001 (admin/admin)"
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
			script {
				// Extract performance metrics for notification
                def performanceMetrics = sh(
                    script: '''
                        if [ -f results/${RESULTS_FILE} ]; then
                            awk -F',' 'NR>1 {
                                total++; rt+=$2;
                                if($8=="true") errors++
                            } END {
                                printf "TOTAL_REQUESTS=%d\\n", total
                                printf "AVG_RESPONSE_TIME=%.0f\\n", rt/total
                                printf "ERROR_RATE=%.1f\\n", errors/total*100
                                printf "SUCCESS_RATE=%.1f\\n", (total-errors)/total*100
                            }' results/${RESULTS_FILE}
                        else
                            echo "TOTAL_REQUESTS=0"
                            echo "AVG_RESPONSE_TIME=0"
                            echo "ERROR_RATE=0"
                            echo "SUCCESS_RATE=0"
                        fi
                    ''',
                    returnStdout: true
                ).trim()

                // Parse metrics
                def metrics = [:]
                performanceMetrics.split('\n').each { line ->
                    def parts = line.split('=')
                    metrics[parts[0]] = parts[1]
                }

                // Determine status colors and messages
                def errorRate = metrics.ERROR_RATE as Float
                def responseTime = metrics.AVG_RESPONSE_TIME as Float
                def successRate = metrics.SUCCESS_RATE as Float

                def slackColor = errorRate > 5 ? 'warning' : 'good'
                def overallStatus = errorRate <= 5 && responseTime <= 2000 ? 'PASS' : 'NEEDS ATTENTION'

                slackSend(
                    color: slackColor,
                    message: """
📊 *PERFORMANCE TEST COMPLETED*
*Job:* ${env.JOB_NAME}
*Build:* #${env.BUILD_NUMBER}
*Test File:* ${params.JMX_FILE}
*Configuration:* ${params.THREADS} users, ${params.DURATION}s duration

📈 *Results Summary:*
- Total Requests: ${metrics.TOTAL_REQUESTS}
- Success Rate: ${metrics.SUCCESS_RATE}%
- Error Rate: ${metrics.ERROR_RATE}%
- Avg Response Time: ${metrics.AVG_RESPONSE_TIME}ms
- Overall Status: ${overallStatus}

🔗 <${env.BUILD_URL}JMeter_20Performance_20Report/|Performance Report> | <${env.BUILD_URL}|Build Details> | <http://localhost:3000|Grafana Dashboard>
                    """
                )

                emailext(
                    subject: "📊 Performance Test Results: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                    body: """
                        <html>
                        <body style="font-family: Arial, sans-serif; color: #333;">
                            <h2 style="color: #2e86c1;">📊 Performance Test Completed</h2>

                            <p>Hello Team,</p>
                            <p>The performance test <b>${env.JOB_NAME} #${env.BUILD_NUMBER}</b> has completed successfully.</p>

                            <h3>🎯 Test Configuration</h3>
                            <table border="1" cellpadding="8" cellspacing="0" style="border-collapse: collapse; margin: 10px 0;">
                                <tr><th align="left" style="background-color: #f8f9fa;">Test Plan</th><td>${params.JMX_FILE}</td></tr>
                                <tr><th align="left" style="background-color: #f8f9fa;">Users</th><td>${params.THREADS} concurrent users</td></tr>
                                <tr><th align="left" style="background-color: #f8f9fa;">Duration</th><td>${params.DURATION} seconds</td></tr>
                                <tr><th align="left" style="background-color: #f8f9fa;">Test Type</th><td>${params.TEST_TYPE}</td></tr>
                            </table>

                            <h3>📈 Performance Results</h3>
                            <table border="1" cellpadding="8" cellspacing="0" style="border-collapse: collapse; margin: 10px 0;">
                                <tr><th align="left" style="background-color: #f8f9fa;">Metric</th><th align="left" style="background-color: #f8f9fa;">Value</th></tr>
                                <tr><td>Total Requests</td><td><b>${metrics.TOTAL_REQUESTS}</b></td></tr>
                                <tr><td>Success Rate</td><td><b>${metrics.SUCCESS_RATE}%</b></td></tr>
                                <tr><td>Error Rate</td><td><b>${metrics.ERROR_RATE}%</b></td></tr>
                                <tr><td>Avg Response Time</td><td><b>${metrics.AVG_RESPONSE_TIME}ms</b></td></tr>
                                <tr><td>Overall Status</td><td><b style="color: ${overallStatus == 'PASS' ? 'green' : 'red'};">${overallStatus}</b></td></tr>
                            </table>

                            <h3>📊 Reports & Dashboards</h3>
                            <ul>
                                <li><a href="${env.BUILD_URL}JMeter_20Performance_20Report/" style="color: blue;">📈 JMeter HTML Report</a></li>
                                <li><a href="http://localhost:3000" style="color: blue;">📊 Grafana Real-time Dashboard</a></li>
                                <li><a href="${env.BUILD_URL}" style="color: blue;">🔧 Jenkins Build Details</a></li>
                                <li><a href="${env.BUILD_URL}console" style="color: blue;">📝 Console Output</a></li>
                            </ul>

                            <p>Regards,<br><b>Performance Testing Team</b></p>
                        </body>
                        </html>
                    """,
                    mimeType: 'text/html',
                    to: "notebooks8.8.8.8@gmail.com"
                )
            }
        }

        failure {
			slackSend(
                color: 'danger',
                message: """
❌ *PERFORMANCE TEST FAILED*
*Job:* ${env.JOB_NAME}
*Build:* #${env.BUILD_NUMBER}
*Test File:* ${params.JMX_FILE}
*Status:* FAILED

*Configuration:* ${params.THREADS} users, ${params.DURATION}s duration

🔗 <${env.BUILD_URL}|Build Details> | <${env.BUILD_URL}console|Console Output>
                """
            )

            emailext(
                subject: "❌ Performance Test Failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: """
                    <html>
                    <body style="font-family: Arial, sans-serif; color: #333;">
                        <h2 style="color: red;">❌ Performance Test Failed</h2>

                        <p>Hello Team,</p>
                        <p>The performance test <b>${env.JOB_NAME} #${env.BUILD_NUMBER}</b> has <span style="color: red; font-weight: bold;">FAILED</span>.</p>

                        <h3>🎯 Test Configuration</h3>
                        <table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse;">
                            <tr><th align="left">Test Plan</th><td>${params.JMX_FILE}</td></tr>
                            <tr><th align="left">Users</th><td>${params.THREADS} concurrent users</td></tr>
                            <tr><th align="left">Duration</th><td>${params.DURATION} seconds</td></tr>
                            <tr><th align="left">Status</th><td style="color: red;"><b>FAILED</b></td></tr>
                        </table>

                        <h3>🔍 Troubleshooting</h3>
                        <p>Please check the console output and build logs for error details.</p>

                        <h3>📎 Links</h3>
                        <ul>
                            <li><a href="${env.BUILD_URL}" style="color: blue;">Jenkins Build Details</a></li>
                            <li><a href="${env.BUILD_URL}console" style="color: blue;">Console Output</a></li>
                        </ul>

                        <p>Regards,<br><b>Performance Testing Team</b></p>
                    </body>
                    </html>
                """,
                mimeType: 'text/html',
                to: "notebooks8.8.8.8@gmail.com"
            )
        }

        cleanup {
			// Optional: Stop containers after test
            sh 'docker-compose down || true'
        }
    }
}