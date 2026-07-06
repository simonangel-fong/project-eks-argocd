INSERT INTO polls (id, title) VALUES
    (1, 'Favorite programming language?'),
    (2, 'Best cloud provider?');

INSERT INTO options (id, poll_id, label) VALUES
    (1, 1, 'Python'),
    (2, 1, 'Go'),
    (3, 1, 'TypeScript'),
    (4, 1, 'Rust'),
    (5, 2, 'AWS'),
    (6, 2, 'Azure'),
    (7, 2, 'GCP');

INSERT INTO votes (poll_id, option_id, voter_id) VALUES
    (1, 1, 'voter-01'),
    (1, 1, 'voter-02'),
    (1, 1, 'voter-03'),
    (1, 2, 'voter-04'),
    (1, 2, 'voter-05'),
    (1, 2, 'voter-06'),
    (1, 3, 'voter-07'),
    (1, 3, 'voter-08'),
    (1, 4, 'voter-09'),
    (1, 4, 'voter-10'),
    (2, 5, 'voter-11'),
    (2, 5, 'voter-12'),
    (2, 5, 'voter-13'),
    (2, 5, 'voter-14'),
    (2, 6, 'voter-15'),
    (2, 6, 'voter-16'),
    (2, 6, 'voter-17'),
    (2, 7, 'voter-18'),
    (2, 7, 'voter-19'),
    (2, 7, 'voter-20');

SELECT setval(pg_get_serial_sequence('polls',   'id'), (SELECT MAX(id) FROM polls));
SELECT setval(pg_get_serial_sequence('options', 'id'), (SELECT MAX(id) FROM options));
