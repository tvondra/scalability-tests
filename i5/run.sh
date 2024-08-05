#!/usr/bin/bash -x

set -e

LABEL=$1
MACHINE=i5
DBNAME=test
RUNS=1
DURATION=10
#CLIENTS="1 2 4 16 32"
CLIENTS="1 4 16"
#PARTITIONS="2000 1000 100 10 1 0"
PARTITIONS="1000 100 10 1 0"
#PARTITIONS="10"
BUILDS="/mnt/data/builds"
SOURCE="/mnt/data/postgres"

PATH_OLD=$PATH

DATE=`date +%Y%m%d-%H%M`

PATCHES=$(pwd)/patches
LOGS=$(pwd)/$DATE-$LABEL/logs
RESULTS=$(pwd)/$DATE-$LABEL/results
DATADIR=/mnt/pgdata/data-test

ulimit -n 35000

# glibc parameter tuning
export MALLOC_TOP_PAD_=$((64*1024*1024))
export MALLOC_MMAP_THRESHOLD_=$((1024*1024))
export MALLOC_TRIM_THRESHOLD_=$((1024*1024))

for files in 1000 32768; do

	for p in $PARTITIONS; do

		for t in pgbench index count join star; do

			# locktable partitions patch
			for partitions in yes no; do

				# fastpath lock groups
				for groups in 32 0 1 1024 8 512 128; do

					LOGDIR=$LOGS/$t-$partitions-$groups-$files-$p
					RESULTDIR=$RESULTS/$t-$partitions-$groups-$files-$p

					mkdir -p $LOGDIR
					mkdir -p $RESULTDIR

					env > $LOGDIR/env.log 2>&1

					echo `date` "BUILD lock partitions: $partitions  fastpath groups: $groups"

					pushd $SOURCE

					git reset --hard
					git checkout master
					git clean -f -d -x > /dev/null

					BRANCH="scalability-$partitions-$groups-$files-$p-$(date +%s)"

					git checkout -b $BRANCH

					if [ "$partitions" == "yes" ]; then
						cat $PATCHES/0001-Increase-NUM_LOCK_PARTITIONS-to-64.patch | patch -p1
						git commit src -m "NUM_LOCK_PARTITIONS"
					fi

					if [ "$groups" != "0" ]; then
						cat $PATCHES/0002-Increase-the-number-of-fastpath-locks.patch | sed "s/MY_PLACEHOLDER/$groups/" | patch -p1
						git commit src -m "fastpath lock groups $groups"
					fi

					# remember the applied patches
					git log | head -n 1000 > $LOGDIR/git.log 2>&1

					# run configure
					CC="ccache gcc" ./configure --prefix=$BUILDS/$partitions-$groups-$files-$p --enable-debug --enable-depend > $LOGDIR/configure.log

					# build everything

					make -s clean
					make -s -j4 install

					cd contrib
					make -s clean
					make -s -j4 install
					cd ..

					popd

					echo `date` "RUN   files: $files  partitions: $p"

					ulimit -a > $LOGDIR/ulimit.log

					export PATH=$BUILDS/$partitions-$groups-$files-$p/bin:$PATH_OLD;

					pg_config > $LOGDIR/debug.log 2>&1

					# make sure postgres is not running already
					killall -9 postgres || true
					sleep 1

					# remove data directory
					rm -Rf $DATADIR

					pg_ctl -D $DATADIR init > $LOGDIR/pginit.log 2>&1

				        echo "max_connections = 1000" >> $DATADIR/postgresql.conf
					echo "shared_buffers = 2GB" >> $DATADIR/postgresql.conf
					echo "max_locks_per_transaction = 8192" >> $DATADIR/postgresql.conf
					echo "max_parallel_workers_per_gather = 0" >> $DATADIR/postgresql.conf
					echo "random_page_cost = 1.5" >> $DATADIR/postgresql.conf
					echo "max_files_per_process = $files" >> $DATADIR/postgresql.conf

					pg_ctl -D $DATADIR -l $LOGDIR/pg.log start > $LOGDIR/start.log 2>&1
					psql postgres -c "select * from pg_settings" > $LOGDIR/settings.log 2>&1

					./run-$t.sh $MACHINE $BRANCH $files $partitions $groups $LOGDIR $RUNS $DURATION "$CLIENTS" "$p" > $RESULTDIR/$t.csv

					pg_ctl -D $DATADIR stop > $LOGDIR/stop.log 2>&1

				done

			done

		done

	done

done
