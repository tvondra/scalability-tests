#!/usr/bin/bash

set -e

MACHINE=$1
BRANCH=$2
NFILES=$3
NPARTS=$4
NGROUPS=$5
OUTDIR=$6
RUNS=$7
DURATION=$8
CLIENTS=$9
PARTITIONS=${10}

ps ax > $OUTDIR/join.ps.log 2>&1

#for s in 1 10 100; do
for s in 1; do

	for p in $PARTITIONS; do

		DBNAME="join-$s-$p"

		cnt=$(psql -t -A -c "select count(*) from pg_database where datname = '$DBNAME'" postgres)

		if [ "$cnt" == "0" ]; then

			createdb $DBNAME >> $OUTDIR/debug.log 2>&1

			if [ "$p" == "0" ]; then
				pgbench -i -s $s $DBNAME >> $OUTDIR/debug.log 2>&1
			else
				pgbench -i -s $s --partitions $p $DBNAME >> $OUTDIR/debug.log 2>&1
			fi

			psql $DBNAME -c "ALTER TABLE pgbench_accounts ADD COLUMN aid_parent INT" >> $OUTDIR/debug.log 2>&1
			psql $DBNAME -c "UPDATE pgbench_accounts SET aid_parent = aid" >> $OUTDIR/debug.log 2>&1

			psql $DBNAME -c "CREATE INDEX ON pgbench_accounts(aid_parent)" >> $OUTDIR/debug.log 2>&1

			psql $DBNAME -c "VACUUM FULL" >> $OUTDIR/debug.log 2>&1

			psql $DBNAME -c "VACUUM ANALYZE" >> $OUTDIR/debug.log 2>&1
			psql $DBNAME -c "CHECKPOINT" >> $OUTDIR/debug.log 2>&1

		fi

		psql $DBNAME -c "\d+" >> $OUTDIR/join.sizes.$s.$p.log 2>&1
		psql $DBNAME -c "\di+" >> $OUTDIR/join.sizes.$s.$p.log 2>&1

		pgbench -n -M prepared -T $((DURATION)) -c 32 -j 32 -f join.sql $DBNAME > $OUTDIR/join-warmup-$s-$p.log 2>&1

		for r in $(seq 1 $RUNS); do

			for m in simple prepared; do

				for c in $CLIENTS; do

					pgbench -n -M $m -T $DURATION -c $c -j $c -f join.sql $DBNAME > $OUTDIR/pgbench.log 2>&1

					lat_avg=$(grep 'latency average' $OUTDIR/pgbench.log | awk '{print $4}')
					lat_stddev=$(grep 'latency stddev' $OUTDIR/pgbench.log | awk '{print $4}')
					tps=$(grep tps $OUTDIR/pgbench.log | awk '{print $3}')

					echo join $MACHINE $BRANCH $NFILES $NPARTS $NGROUPS $s $p $m $c $r $tps $lat_avg $lag_stddev

				done

			done

		done

	done

done
