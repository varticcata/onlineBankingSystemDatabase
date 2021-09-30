-- PROCEDURE shows transactions from specific period of time for an account
DELIMITER $$
DROP PROCEDURE IF EXISTS ShowTransactions;
CREATE PROCEDURE ShowTransactions(IN AccountId INT, IN StartDate DATE, IN EndDate DATE)
BEGIN
SELECT t.ID, t.account_id, tt.type, t.amount, t.status, t.date FROM transactions t
JOIN transaction_types tt
	on tt.ID = t.typeOfTransaction
 WHERE account_id = AccountId AND date BETWEEN StartDate AND EndDate;
END $$
DELIMITER ;

-- execution of the procedure
-- CALL ShowTransactions(23, '2012-1-1', '2021-6-30');


-- TRIGGER  update balance after new transaction
DELIMITER $$
CREATE TRIGGER update_balance
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    UPDATE accounts a
    SET balance = IF(new.status = 'received', balance + new.amount, balance - new.amount)
    WHERE a.id = NEW.account_id;
END $$
DELIMITER ;


-- EVENT account fee is taken from account each year (in the beginning of the year)
DELIMITER $$
DROP EVENT IF EXISTS account_fee;
CREATE EVENT account_fee
ON SCHEDULE EVERY 1 YEAR
STARTS '2021-01-01' ENDS '2031-01-01'
DO BEGIN
    DECLARE accountId INT;
    DECLARE amountFee DECIMAL(5,2);
    DROP TEMPORARY TABLE IF EXISTS temp;
    CREATE TEMPORARY TABLE temp AS
    SELECT a.id, t.fee FROM accounts a
     JOIN account_type t ON a.typeOfAccount = t.id;
    WHILE (SELECT COUNT(*) FROM temp) > 0
    DO
        SELECT id, fee FROM temp LIMIT 0, 1 INTO accountId, amountFee;
        IF amountFee != 0 THEN
            INSERT INTO transactions(typeOfTransaction, account_id, amount, status, date)
                VALUES (8, accountId, amountFee, 'spend', CURDATE());
            DELETE FROM temp WHERE id = accountId;
        END IF;
    END WHILE;
END $$
DELIMITER ;


-- VIEW
-- name together, balance, total received, total send
CREATE OR REPLACE VIEW onlinebankingsystem.money_movements
AS
SELECT
	CONCAT(c.firstName, c.lastName) as name,
    a.balance,
    t.account_id,
	SUM(IF(t.status='received', t.amount, NULL)) AS received,
	SUM(IF(t.status = 'spend', t.amount, NULL)) AS spend

FROM clients c

JOIN account_customers ac
	ON c.ID = ac.client_id
JOIN accounts a
	ON ac.account_id = a.ID
JOIN transactions t
	ON a.ID = t.account_id
    GROUP BY name;


-- FUNCTION check if employee is also a customer
DELIMITER $$
CREATE FUNCTION CheckEmployee(IN employee_ssn varchar(11))
RETURNS VARCHAR(5)
DETERMINISTIC
BEGIN
    IF SELECT EXISTS (SELECT * FROM clients WHERE ssn = employee_ssn)
    THEN RETURN 'TRUE';
    ELSE RETURN 'FALSE';
    END IF;
END $$
DELIMITER ;

-- SELECT CheckEmployee('300-01-2000');


-- PROCEDURE highest transaction made from users account
DELIMITER $$
DROP PROCEDURE IF EXISTS highestTransaction;
CREATE PROCEDURE highestTransaction(IN accountId INT)
BEGIN
    SELECT a.accountNumber, MAX(t.amount) AS 'Highest transaction', tt.type, t.status, t.date
    FROM transactions t
    JOIN transaction_types tt ON t.typeOfTransaction = tt.id
    JOIN accounts a ON a.id = t.account_id WHERE a.id = accountId;
END $$
DELIMITER ;

-- CALL highestTransaction(8);


-- PROCEDURE show how many months does the user has till the end of the loan
DELIMITER $$
DROP PROCEDURE IF EXISTS loan_duration_left;
CREATE PROCEDURE loan_duration_left(IN accountId INT)
BEGIN
   SELECT IF(period - TIMESTAMPDIFF(MONTH, date, NOW()) > 0, period - TIMESTAMPDIFF(MONTH, date, NOW()), 'Closed') AS 'Months left' FROM loans WHERE account_id = accountId;
END $$
DELIMITER ;

-- CALL loan_duration_left(8);

-- EVENT add 10% of months 'spend' money back
DELIMITER $$
DROP EVENT IF EXISTS cashback;
CREATE EVENT cashback
ON SCHEDULE EVERY 1 MONTH
STARTS '2021-10-01'
DO BEGIN
    DECLARE accountId INT;
    DECLARE cashback_amount DECIMAL(9,2);
    DROP TEMPORARY TABLE IF EXISTS temp;
    CREATE TEMPORARY TABLE temp AS
    SELECT account_id, SUM(IF(status = 'spend', amount, 0)) as 'spend' FROM transactions WHERE date BETWEEN DATE_SUB(NOW(), INTERVAL 1 MONTH) AND NOW() GROUP BY account_id;
    WHILE (SELECT COUNT(*) FROM temp) > 0
        DO
          SELECT account_id, spend * 0.1 FROM temp LIMIT 0, 1 INTO accountId, cashback_amount;
          INSERT INTO transactions(typeOfTransaction, account_id, amount, status, date)
                VALUES (9, accountId, cashback_amount, 'received', CURDATE());
          DELETE FROM temp WHERE account_id = accountId;
    END WHILE;
END $$
DELIMITER ;

-- TRIGGER check before transaction that user has enough money
DELIMITER $$
DROP TRIGGER IF EXISTS check_balance;
CREATE TRIGGER check_balance
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE account_balance DECIMAL(9,2);
    DECLARE errorMessage varchar(255);
    SET errorMessage = CONCAT('You don\'t have enough balance for executing the transaction');
    IF NEW.status = 'spend' THEN
        SELECT balance FROM accounts a  WHERE a.id = NEW.account_id INTO account_balance;
        IF account_balance < NEW.amount THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = errorMessage;
        END IF;
    END IF;
END $$
DELIMITER ;

-- INSERT INTO transactions VALUES (1, 1, 1, 20071.9, 'spend', '2021-09-26');

--FUNCTION check if person has a loan
DELIMITER $$
CREATE FUNCTION CheckLoan(ssnclient varchar(11))
RETURNS varchar(5)
DETERMINISTIC
BEGIN
	IF EXISTS (
    SELECT * FROM loans l
    JOIN accounts a
		on a.ID = l.account_id
	JOIN account_customers ac
		on ac.account_id = a.ID
	JOIN clients c
		on c.ID = ac.client_id
	WHERE c.ssn = ssnclient)
    THEN RETURN 'TRUE';
    ELSE RETURN 'FALSE';
    END IF;
END$$
DELIMITER ;

-- SELECT CheckLoan('300-01-2000');

-- VIEW name, last name, account number, bank, loan (function to check if there is a loan to the user)
CREATE VIEW loan_state as
select
c.firstName,
c.lastName,
c.ssn,
a.accountNumber,
b.name,
CheckLoan(c.ssn) as loan

FROM clients c
JOIN account_customers ac
	on c.ID = ac.client_id
JOIN accounts a
	on a.ID = ac.account_id
JOIN bank b
	on b.ID = a.bank_id;


DELIMITER $$
DROP PROCEDURE IF EXISTS Show_Cards;
CREATE PROCEDURE Show_Cards(IN ssnclient VARCHAR(11))
BEGIN
    SELECT c.firstName, c.lastName, dct.type, dc.number, dc.expiry_date, 'Credit Card' as '' FROM debit_cards dc
    JOIN debit_card_types dct ON dc.typeOfCard = dct.id
    JOIN account_customers ac ON ac.account_id = dc.account_id
    JOIN clients c ON c.id = ac.client_id WHERE c.ssn = ssnclient
    UNION
    SELECT c.firstName, c.lastName, cct.type, cc.number, cc.expiry_date, 'Debit Card' as '' FROM credit_cards cc
    JOIN credit_card_types cct ON cc.typeOfCard = cct.id
    JOIN account_customers ac ON ac.account_id = cc.account_id
    JOIN clients c ON c.id = ac.client_id WHERE c.ssn = ssnclient;
END $$
DELIMITER ;

-- CALL Show_Cards('300-01-2000');
