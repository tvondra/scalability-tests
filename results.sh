#!/usr/bin/bash

for t in index pgbench star count join; do

	rm -f $t.csv

	cat */$t.csv > $t.csv

done
