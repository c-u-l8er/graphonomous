#!/bin/bash
cd /home/travis/ProjectAmp2/graphonomous
source .env.rescore
exec mix benchmark.longmemeval_rescore --input longmemeval_20260405_234227_ppr0.18_L500.json --limit "${1:-500}" --concurrency 4 2>&1
