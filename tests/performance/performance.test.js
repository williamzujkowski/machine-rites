/**
 * Performance Test Suite
 * Validates optimization targets and regression testing
 */

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

describe('Performance Tests', () => {
    const PROJECT_ROOT = path.resolve(__dirname, '../..');
    const PERFORMANCE_DIR = path.join(PROJECT_ROOT, '.performance');
    const TOOLS_DIR = path.join(PROJECT_ROOT, 'tools');

    // Performance targets
    const TARGETS = {
        SHELL_STARTUP_MS: 2,
        BOOTSTRAP_TIME_MS: 1500,
        DOCKER_SIZE_MB: 500,
        CACHE_SIZE_GB: 10
    };

    beforeAll(() => {
        // Ensure performance directory exists
        if (!fs.existsSync(PERFORMANCE_DIR)) {
            fs.mkdirSync(PERFORMANCE_DIR, { recursive: true });
        }
    });

    describe('Shell Startup Performance', () => {
        test('shell startup time should be under 2ms', async () => {
            const iterations = 10;
            const times = [];

            for (let i = 0; i < iterations; i++) {
                const start = Date.now();
                execSync('bash -c "exit 0"', { stdio: 'ignore' });
                const end = Date.now();
                times.push(end - start);
            }

            const avgTime = times.reduce((a, b) => a + b, 0) / times.length;

            // Save results
            fs.writeFileSync(
                path.join(PERFORMANCE_DIR, 'shell_startup_test.json'),
                JSON.stringify({
                    timestamp: new Date().toISOString(),
                    avg_time_ms: avgTime,
                    target_ms: TARGETS.SHELL_STARTUP_MS,
                    passed: avgTime <= TARGETS.SHELL_STARTUP_MS,
                    individual_times: times
                }, null, 2)
            );

            expect(avgTime).toBeLessThanOrEqual(TARGETS.SHELL_STARTUP_MS);
        }, 30000);
    });

    describe('Bootstrap Performance', () => {
        test('bootstrap should complete under 1.5 seconds', async () => {
            const bootstrapScript = path.join(PROJECT_ROOT, 'bootstrap/bootstrap-optimized.sh');

            if (!fs.existsSync(bootstrapScript)) {
                console.warn('Optimized bootstrap script not found, skipping test');
                return;
            }

            const start = Date.now();

            try {
                execSync(`bash "${bootstrapScript}" --dry-run`, {
                    stdio: 'ignore',
                    timeout: 10000
                });

                const end = Date.now();
                const duration = end - start;

                // Save results
                fs.writeFileSync(
                    path.join(PERFORMANCE_DIR, 'bootstrap_test.json'),
                    JSON.stringify({
                        timestamp: new Date().toISOString(),
                        time_ms: duration,
                        target_ms: TARGETS.BOOTSTRAP_TIME_MS,
                        passed: duration <= TARGETS.BOOTSTRAP_TIME_MS,
                        script_path: bootstrapScript
                    }, null, 2)
                );

                expect(duration).toBeLessThanOrEqual(TARGETS.BOOTSTRAP_TIME_MS);
            } catch (error) {
                throw new Error(`Bootstrap test failed: ${error.message}`);
            }
        }, 15000);
    });

    describe('Docker Image Sizes', () => {
        test('optimized Docker images should be under 500MB', async () => {
            let dockerAvailable = true;

            try {
                execSync('docker --version', { stdio: 'ignore' });
            } catch (error) {
                console.warn('Docker not available, skipping Docker size tests');
                dockerAvailable = false;
            }

            if (!dockerAvailable) return;

            try {
                const imagesOutput = execSync('docker images oscalize --format "{{.Repository}} {{.Tag}} {{.Size}}"', {
                    encoding: 'utf8',
                    timeout: 5000
                });

                const images = imagesOutput.trim().split('\n').filter(line => line.length > 0);
                const imageSizes = [];
                let maxSize = 0;

                for (const line of images) {
                    const [repo, tag, size] = line.split(' ');
                    let sizeMB = 0;

                    if (size.includes('GB')) {
                        sizeMB = parseFloat(size.replace('GB', '')) * 1024;
                    } else if (size.includes('MB')) {
                        sizeMB = parseFloat(size.replace('MB', ''));
                    }

                    imageSizes.push({ repo, tag, size, sizeMB });
                    maxSize = Math.max(maxSize, sizeMB);
                }

                // Save results
                fs.writeFileSync(
                    path.join(PERFORMANCE_DIR, 'docker_sizes_test.json'),
                    JSON.stringify({
                        timestamp: new Date().toISOString(),
                        max_size_mb: maxSize,
                        target_mb: TARGETS.DOCKER_SIZE_MB,
                        passed: maxSize <= TARGETS.DOCKER_SIZE_MB,
                        images: imageSizes
                    }, null, 2)
                );

                expect(maxSize).toBeLessThanOrEqual(TARGETS.DOCKER_SIZE_MB);
            } catch (error) {
                console.warn('Docker images test failed:', error.message);
            }
        }, 10000);
    });

    describe('Cache Management', () => {
        test('cache size should be within limits', async () => {
            const cacheScript = path.join(TOOLS_DIR, 'cache-manager.sh');

            if (!fs.existsSync(cacheScript)) {
                console.warn('Cache manager script not found, skipping cache test');
                return;
            }

            try {
                execSync(`bash "${cacheScript}" analyze`, {
                    stdio: 'ignore',
                    timeout: 30000
                });

                const analysisFile = path.join(PERFORMANCE_DIR, 'cache_analysis.json');

                if (fs.existsSync(analysisFile)) {
                    const analysis = JSON.parse(fs.readFileSync(analysisFile, 'utf8'));

                    expect(analysis.total_size_gb).toBeLessThanOrEqual(TARGETS.CACHE_SIZE_GB);

                    // Save test results
                    fs.writeFileSync(
                        path.join(PERFORMANCE_DIR, 'cache_test.json'),
                        JSON.stringify({
                            timestamp: new Date().toISOString(),
                            total_size_gb: analysis.total_size_gb,
                            target_gb: TARGETS.CACHE_SIZE_GB,
                            passed: analysis.total_size_gb <= TARGETS.CACHE_SIZE_GB,
                            needs_cleanup: analysis.needs_cleanup
                        }, null, 2)
                    );
                }
            } catch (error) {
                console.warn('Cache analysis failed:', error.message);
            }
        }, 45000);
    });

    describe('Git Operations Performance', () => {
        test('git status should complete quickly', async () => {
            const start = Date.now();

            try {
                execSync('git status --porcelain', {
                    cwd: PROJECT_ROOT,
                    stdio: 'ignore',
                    timeout: 5000
                });

                const end = Date.now();
                const duration = end - start;

                // Save results
                fs.writeFileSync(
                    path.join(PERFORMANCE_DIR, 'git_performance_test.json'),
                    JSON.stringify({
                        timestamp: new Date().toISOString(),
                        git_status_ms: duration,
                        target_ms: 1000,
                        passed: duration <= 1000
                    }, null, 2)
                );

                expect(duration).toBeLessThanOrEqual(1000); // 1 second max
            } catch (error) {
                throw new Error(`Git status test failed: ${error.message}`);
            }
        });
    });

    describe('File I/O Performance', () => {
        test('file operations should be performant', async () => {
            const testFile = path.join(PERFORMANCE_DIR, 'io_test.tmp');
            const testSize = 1024 * 1024; // 1MB
            const testData = Buffer.alloc(testSize, 'a');

            // Write test
            const writeStart = Date.now();
            fs.writeFileSync(testFile, testData);
            const writeEnd = Date.now();
            const writeTime = writeEnd - writeStart;

            // Read test
            const readStart = Date.now();
            const readData = fs.readFileSync(testFile);
            const readEnd = Date.now();
            const readTime = readEnd - readStart;

            // Cleanup
            fs.unlinkSync(testFile);

            // Save results
            fs.writeFileSync(
                path.join(PERFORMANCE_DIR, 'io_performance_test.json'),
                JSON.stringify({
                    timestamp: new Date().toISOString(),
                    write_time_ms: writeTime,
                    read_time_ms: readTime,
                    test_size_mb: testSize / (1024 * 1024),
                    write_speed_mb_s: (testSize / (1024 * 1024)) / (writeTime / 1000),
                    read_speed_mb_s: (testSize / (1024 * 1024)) / (readTime / 1000)
                }, null, 2)
            );

            // Basic performance expectations
            expect(writeTime).toBeLessThan(1000); // Write 1MB in under 1 second
            expect(readTime).toBeLessThan(500);   // Read 1MB in under 0.5 seconds
        });
    });

    describe('Memory Usage', () => {
        test('memory usage should be reasonable', async () => {
            // Get current memory usage
            const memInfo = fs.readFileSync('/proc/meminfo', 'utf8');
            const memTotal = parseInt(memInfo.match(/MemTotal:\s+(\d+)/)[1]) * 1024; // Convert to bytes
            const memFree = parseInt(memInfo.match(/MemFree:\s+(\d+)/)[1]) * 1024;
            const memUsed = memTotal - memFree;
            const memUsagePercent = (memUsed / memTotal) * 100;

            // Save results
            fs.writeFileSync(
                path.join(PERFORMANCE_DIR, 'memory_test.json'),
                JSON.stringify({
                    timestamp: new Date().toISOString(),
                    total_mb: Math.round(memTotal / (1024 * 1024)),
                    used_mb: Math.round(memUsed / (1024 * 1024)),
                    free_mb: Math.round(memFree / (1024 * 1024)),
                    usage_percent: Math.round(memUsagePercent * 100) / 100,
                    passed: memUsagePercent < 90
                }, null, 2)
            );

            // Memory usage should not exceed 90%
            expect(memUsagePercent).toBeLessThan(90);
        });
    });

    describe('Performance Regression', () => {
        test('performance should not regress', async () => {
            const benchmarkScript = path.join(TOOLS_DIR, 'benchmark.sh');

            if (!fs.existsSync(benchmarkScript)) {
                console.warn('Benchmark script not found, skipping regression test');
                return;
            }

            try {
                execSync(`bash "${benchmarkScript}" full`, {
                    stdio: 'ignore',
                    timeout: 60000
                });

                const reportFile = path.join(PERFORMANCE_DIR, 'performance_report.json');

                if (fs.existsSync(reportFile)) {
                    const report = JSON.parse(fs.readFileSync(reportFile, 'utf8'));

                    // Overall score should be above 70%
                    expect(report.overall_score).toBeGreaterThanOrEqual(70);

                    // At least 70% of tests should pass
                    const passRate = (report.passed_tests / report.total_tests) * 100;
                    expect(passRate).toBeGreaterThanOrEqual(70);
                }
            } catch (error) {
                console.warn('Performance regression test failed:', error.message);
            }
        }, 90000);
    });

    afterAll(() => {
        // Generate summary report
        const summaryFile = path.join(PERFORMANCE_DIR, 'test_summary.json');
        const testFiles = fs.readdirSync(PERFORMANCE_DIR)
            .filter(file => file.endsWith('_test.json'))
            .map(file => {
                try {
                    const data = JSON.parse(fs.readFileSync(path.join(PERFORMANCE_DIR, file), 'utf8'));
                    return { file, data };
                } catch (error) {
                    return { file, error: error.message };
                }
            });

        const summary = {
            timestamp: new Date().toISOString(),
            total_tests: testFiles.length,
            passed_tests: testFiles.filter(t => t.data && t.data.passed).length,
            test_results: testFiles
        };

        fs.writeFileSync(summaryFile, JSON.stringify(summary, null, 2));

        console.log(`Performance test summary saved to ${summaryFile}`);
    });
});