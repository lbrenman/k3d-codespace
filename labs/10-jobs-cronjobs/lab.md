# Lab 10: Jobs & CronJobs — Batch Workloads
# ─────────────────────────────────────────────────────────────────────────────
#
# Not everything in Kubernetes is a long-running server. Jobs and CronJobs
# handle batch workloads — tasks that run to completion rather than forever.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# Deployment vs Job vs CronJob:
#
#   ┌───────────────┬──────────────────────────────────────────────────┐
#   │  Deployment   │ Long-running service. Restarts if it stops.      │
#   │               │ e.g. web server, API, database                   │
#   ├───────────────┼──────────────────────────────────────────────────┤
#   │  Job          │ Runs to completion once. Not restarted after     │
#   │               │ success. e.g. DB migration, report generation,   │
#   │               │ data import, one-off scripts                     │
#   ├───────────────┼──────────────────────────────────────────────────┤
#   │  CronJob      │ Runs a Job on a schedule (cron syntax).          │
#   │               │ e.g. nightly backups, hourly cleanup,            │
#   │               │ daily reports, cache invalidation                │
#   └───────────────┴──────────────────────────────────────────────────┘
#
# What you will build:
#
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: lab10                                                 │
#   │                                                                  │
#   │  Section A — Simple Job (runs once, completes)                  │
#   │  Section B — Parallel Job (multiple pods, multiple completions)  │
#   │  Section C — CronJob (runs on a schedule)                       │
#   │  Section D — Job with retry on failure                          │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: Job, CronJob, completions, parallelism, backoffLimit,
#               restartPolicy, concurrencyPolicy, cron syntax

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab10

# ════════════════════════════════════════════════════════════════════════════
# SECTION A: Simple Job
# ════════════════════════════════════════════════════════════════════════════

# ── Step 2: Create a simple Job ───────────────────────────────────────────────
# This job calculates pi to 2000 decimal places then exits successfully.
# Key difference from a Deployment: restartPolicy must be Never or OnFailure
# (not Always, which is the Deployment default).
kubectl apply -n lab10 -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: pi-calculator
spec:
  template:
    spec:
      restartPolicy: Never       # Do not restart after completion
      containers:
      - name: pi
        image: perl:slim
        command:
        - perl
        - -Mbignum=bpi
        - -wle
        - "print bpi(2000)"
YAML

# ── Step 3: Watch the Job run and complete ───────────────────────────────────
kubectl get jobs -n lab10 -w
# COMPLETIONS will go from 0/1 to 1/1 once done
# Press Ctrl+C

kubectl get pods -n lab10
# STATUS will show Completed (not Running or Restarting)

# ── Step 4: Read the Job output ───────────────────────────────────────────────
# Pods created by Jobs are kept after completion so you can read their logs
JOB_POD=$(kubectl get pods -n lab10 -l job-name=pi-calculator -o jsonpath='{.items[0].metadata.name}')
kubectl logs $JOB_POD -n lab10
# You should see 2000 digits of pi

# Inspect the Job status
kubectl describe job pi-calculator -n lab10

# ════════════════════════════════════════════════════════════════════════════
# SECTION B: Parallel Job
# ════════════════════════════════════════════════════════════════════════════
#
# Jobs can run multiple pods in parallel and require multiple completions.
# Useful for processing a queue of work items concurrently.

# ── Step 5: Create a parallel Job ────────────────────────────────────────────
# completions: total number of successful pod runs required
# parallelism: how many pods to run at the same time
kubectl apply -n lab10 -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: parallel-job
spec:
  completions: 6      # Need 6 successful completions total
  parallelism: 2      # Run 2 pods at a time
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "Worker pod $(hostname) starting..."
          sleep $((RANDOM % 5 + 3))
          echo "Worker pod $(hostname) done"
YAML

# ── Step 6: Watch parallel execution ─────────────────────────────────────────
kubectl get jobs parallel-job -n lab10 -w
# COMPLETIONS increments as pods finish, 2 at a time
# Press Ctrl+C when COMPLETIONS shows 6/6

kubectl get pods -n lab10 -l job-name=parallel-job
# You should see 6 Completed pods

# ════════════════════════════════════════════════════════════════════════════
# SECTION C: CronJob
# ════════════════════════════════════════════════════════════════════════════
#
# CronJobs create a Job on a schedule using standard cron syntax:
#   ┌──────── minute (0-59)
#   │ ┌────── hour (0-23)
#   │ │ ┌──── day of month (1-31)
#   │ │ │ ┌── month (1-12)
#   │ │ │ │ ┌ day of week (0-6, 0=Sunday)
#   │ │ │ │ │
#   * * * * *
#
# Examples:
#   "0 * * * *"   — every hour at :00
#   "0 2 * * *"   — every day at 2am
#   "*/5 * * * *" — every 5 minutes
#   "0 9 * * 1"   — every Monday at 9am

# ── Step 7: Create a CronJob that runs every minute ──────────────────────────
# (Every minute is impractical in production but useful for lab observation)
kubectl apply -n lab10 -f - <<YAML
apiVersion: batch/v1
kind: CronJob
metadata:
  name: logger
spec:
  schedule: "*/1 * * * *"     # Every minute
  concurrencyPolicy: Forbid   # Don't start a new job if previous is still running
  successfulJobsHistoryLimit: 3   # Keep last 3 completed jobs
  failedJobsHistoryLimit: 1       # Keep last 1 failed job
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: logger
            image: busybox:latest
            command:
            - /bin/sh
            - -c
            - echo "CronJob ran at $(date)"
YAML

kubectl get cronjob -n lab10
# SCHEDULE shows the cron expression, LAST SCHEDULE shows last run time

# ── Step 8: Watch CronJob fire ────────────────────────────────────────────────
# Wait up to 60 seconds for the first run
kubectl get jobs -n lab10 -w
# You will see a new job appear each minute named logger-<timestamp>
# Press Ctrl+C after you see 2-3 jobs

# List the jobs the CronJob created
kubectl get jobs -n lab10

# Read logs from the most recent CronJob pod
CRON_POD=$(kubectl get pods -n lab10 -l app.kubernetes.io/name=logger \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || \
  kubectl get pods -n lab10 --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
kubectl logs $CRON_POD -n lab10

# ── Step 9: Manually trigger a CronJob ───────────────────────────────────────
# You can create an immediate Job from a CronJob without waiting for the schedule
kubectl create job logger-manual \
  --from=cronjob/logger \
  -n lab10

kubectl get pods -n lab10 -w
# Press Ctrl+C once the manual job completes

kubectl logs -n lab10 -l job-name=logger-manual

# ── Step 10: Suspend the CronJob ──────────────────────────────────────────────
# Suspend stops future scheduled runs without deleting anything
kubectl patch cronjob logger -n lab10 -p '{"spec":{"suspend":true}}'
kubectl get cronjob -n lab10
# SUSPEND column will show True

# Resume it
kubectl patch cronjob logger -n lab10 -p '{"spec":{"suspend":false}}'

# ════════════════════════════════════════════════════════════════════════════
# SECTION D: Job failure handling and retries
# ════════════════════════════════════════════════════════════════════════════

# ── Step 11: Create a Job that fails and retries ──────────────────────────────
# backoffLimit controls how many times K8s retries a failed Job before giving up
kubectl apply -n lab10 -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: failing-job
spec:
  backoffLimit: 3        # Retry up to 3 times before marking as Failed
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: app
        image: busybox:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "Attempting task..."
          exit 1           # Always fail
YAML

# ── Step 12: Watch the retries ────────────────────────────────────────────────
kubectl get pods -n lab10 -l job-name=failing-job -w
# You will see 4 pods created total (1 original + 3 retries), all with Error status
# Press Ctrl+C

kubectl describe job failing-job -n lab10
# Events will show: "Job has reached the specified backoff limit"

kubectl get job failing-job -n lab10
# COMPLETIONS will show 0/1 and CONDITIONS will show Failed

# ── Step 13: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab10


# ── Further Reading ───────────────────────────────────────────────────────────
# Jobs:
#   https://kubernetes.io/docs/concepts/workloads/controllers/job/
# CronJobs:
#   https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/
# Cron syntax reference:
#   https://en.wikipedia.org/wiki/Cron#CRON_expression
# Running automated tasks with CronJobs (official tutorial):
#   https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/
