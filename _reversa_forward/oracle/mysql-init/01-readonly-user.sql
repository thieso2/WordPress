-- The rebuild's one-way seeding connection (lib/seeding/legacy.rb): SELECT and nothing else.
CREATE USER IF NOT EXISTS 'wporacle_ro'@'%' IDENTIFIED BY 'oracle';
GRANT SELECT ON wp_oracle.* TO 'wporacle_ro'@'%';
FLUSH PRIVILEGES;
