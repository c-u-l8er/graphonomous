#!/bin/bash
cd /tmp/claude-1000/-home-travis-ProjectAmp2/ac8f93a5-7380-4895-ae54-fd98459289cc/scratchpad/gpr0/bench
: > results_big.jsonl
for e in fa2 d3force hpcc viz elk dagre cydagre fcose; do
  timeout 240 node bench.mjs $e 2000 10000 >> results_big.jsonl 2>>errors_big.txt
  rc=$?; [ $rc -ne 0 ] && echo "{\"engine\":\"$e\",\"n\":2000,\"status\":\"timeout_or_error rc=$rc\"}" >> results_big.jsonl
done
echo DONE >> results_big.jsonl
