-- Account deletion: the install-id hash of a deleted account stays here, with no link to any person, so that deleting
-- and re-creating an account cannot claim the Free credits again on the same Mac.
CREATE TABLE deleted_installs (
  install_id_hash TEXT PRIMARY KEY,
  deleted_at INTEGER NOT NULL
);
