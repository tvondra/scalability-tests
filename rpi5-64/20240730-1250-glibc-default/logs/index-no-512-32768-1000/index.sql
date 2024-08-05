\set aid random(1, 100000 * 1)
select * from t where id = :aid;
