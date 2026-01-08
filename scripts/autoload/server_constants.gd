extends Node
## ServerConstants - Locked constants for server lifecycle
##
## DO NOT CHANGE THESE unless you understand the implications.
## Changes require matching updates in:
## - ZSDU.Backend/Config.cs (HeartbeatTimeoutSeconds)
## - HeadlessServer.gd

# ============================================
# LOCKED CONSTANTS
# ============================================

## Heartbeat interval - how often server reports to backend
## 2s survives brief GC/physics spikes while staying responsive
const HEARTBEAT_INTERVAL_SEC := 2.0

## Heartbeat timeout - backend marks server dead after this
## 6s = 3 missed heartbeats before death
const HEARTBEAT_TIMEOUT_SEC := 6.0

## Empty shutdown delay - server exits after being empty this long
## 30s prevents server churn while being responsive
const EMPTY_SHUTDOWN_DELAY_SEC := 30.0

## Ready retry interval - time between /servers/ready retries
const READY_RETRY_INTERVAL_SEC := 2.0

## Ready max retries - give up after this many failures
const READY_MAX_RETRIES := 15
