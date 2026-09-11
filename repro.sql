CREATE TABLE t (id int PRIMARY KEY, a int);
INSERT INTO t VALUES (1, 10), (2, 20);

-- Matches one row and leaves its value as it is.
UPDATE t SET a = a WHERE id = 1;

-- Matches both rows, but only row 2 gets a new value.
UPDATE t SET a = 10;

SELECT * FROM t ORDER BY id;
