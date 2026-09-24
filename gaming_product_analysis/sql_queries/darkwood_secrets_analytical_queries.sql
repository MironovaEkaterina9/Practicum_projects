/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
*/

-- ============================================================================
-- Часть 1. ИССЛЕДОВАТЕЛЬСКИЙ АНАЛИЗ ДАННЫХ
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Задача 1. Исследование доли платящих игроков
-- ----------------------------------------------------------------------------

-- 1.1. Расчет доли платящих пользователей по всем данным:

SELECT total_users,
		payer_users,
		ROUND((CAST(payer_users AS numeric) / total_users) * 100, 2)  AS share_of_payers_pct
FROM (SELECT COUNT(id) AS total_users,
		(SELECT COUNT(id) FROM fantasy.users WHERE payer = 1) AS payer_users
FROM fantasy.users) AS all_users; 

-- 1.2. Расчет конверсии в платящего игрока в разрезе рас персонажей:

SELECT race,
		COUNT(id) AS total_users,
		SUM(payer) AS payer_users,
		CAST(SUM(payer) AS float) / COUNT(id) AS share_race_payers
FROM fantasy.users AS u
LEFT JOIN fantasy.race AS r USING (race_id)
GROUP BY race
ORDER BY share_race_payers DESC;

-- ----------------------------------------------------------------------------
-- Задача 2. Исследование внутриигровых покупок и эпических предметов
-- ----------------------------------------------------------------------------

-- 2.1. Сравнительный анализ описательной статистики (с нулевыми покупками и без):

SELECT 'with 0 amount' AS category,
		COUNT(amount) AS total_amount,
		SUM(amount) AS sum_amount,
		MIN(amount) AS min_amount,
		MAX(amount) AS max_amount,
		AVG(amount) AS avg_amount,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median,
		STDDEV(amount) AS stand_dev
FROM fantasy.events
UNION ALL
SELECT 'without 0 amount' AS category,
		COUNT(amount) AS total_amount,
		SUM(amount) AS sum_amount,
		MIN(amount) AS min_amount,
		MAX(amount) AS max_amount,
		AVG(amount) AS avg_amount,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median,
		STDDEV(amount) AS stand_dev
FROM fantasy.events
WHERE amount > 0;

-- 2.2: Структурный анализ аномальных транзакций с нулевой стоимостью:

SELECT race,
		item_code,
		COUNT(*) AS total_0_amount,
		CAST(COUNT(*) AS float) / (SELECT COUNT(*) FROM fantasy.events) * 100 AS share_0_amount
FROM fantasy.events AS e
LEFT JOIN fantasy.users AS u USING (id)
LEFT JOIN fantasy.race AS r USING (race_id)
WHERE amount = 0
GROUP BY race, item_code
ORDER BY total_0_amount DESC;

-- 2.3: Формирование рейтинга популярности и востребованности эпических предметов (исключая нулевые покупки):

WITH
-- Считаем долю уникальных покупателей для каждого предмета
item_buyers AS (
	SELECT item_code AS unique_item,
			i.game_items,
			CAST(COUNT(DISTINCT id) AS float) / (SELECT COUNT(DISTINCT id) FROM fantasy.events WHERE amount > 0) AS share_item_buyers	
	FROM fantasy.events AS e
	LEFT JOIN fantasy.items AS i USING (item_code)
	WHERE amount > 0
	GROUP BY item_code, i.game_items
			)
			
SELECT poi.unique_item,
		ib.game_items,
		poi.total_transaction_item,
		CAST(poi.total_transaction_item AS float) / poi.total_transaction AS share_total_transaction_item,
		ib.share_item_buyers
FROM (
	  SELECT item_code AS unique_item,
		SUM(COUNT(transaction_id)) OVER() AS total_transaction,
		COUNT(transaction_id)  AS total_transaction_item
	  FROM fantasy.events
	  WHERE amount > 0
	  GROUP BY item_code ) AS poi
INNER JOIN item_buyers AS ib ON ib.unique_item = poi.unique_item
ORDER BY share_item_buyers DESC;

-- ============================================================================
-- Часть 2. Решение ad hoc-задачи
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Задача: Изучить активность игроков при покупке эпических предметов в разрезе разных рас персонажей
-- Гипотеза: Игра за некоторые расы сложнее и требует большего количества покупок эпических предметов, которые помогают в прохождении
-- ----------------------------------------------------------------------------

WITH 
-- Общее количество зарегистрированных игроков по id расы
total_race_users AS (
	SELECT race_id,
		COUNT(id) AS race_users
	FROM fantasy.users
	GROUP BY race_id
	),
-- Количество игроков с покупками (amount > 0) по id расы
buyer_race AS (
	SELECT u.race_id,
		COUNT(DISTINCT u.id) AS buyer_users
	FROM fantasy.events AS e 
	LEFT JOIN fantasy.users AS u USING (id)
	WHERE amount > 0
	GROUP BY u.race_id
	),
-- Количество уникальных платящих (payer = 1) игроков по id расы
payer_race AS (
	SELECT u.race_id,
		COUNT(DISTINCT id) AS payer_users
	FROM fantasy.events AS e 
	LEFT JOIN fantasy.users AS u USING (id)
	WHERE amount > 0 AND payer = 1
	GROUP BY u.race_id
	),
-- Расчет базовых агрегатов (суммы и количества транзакций) по id расы
metrics_race AS (
	SELECT u.race_id,
	       COUNT(e.transaction_id) AS total_trans,
	       COUNT(DISTINCT e.id) AS unique_buyers,
	       SUM(e.amount) AS total_amount
	FROM fantasy.events AS e
	LEFT JOIN fantasy.users AS u USING (id)
	WHERE amount > 0
	GROUP BY u.race_id
)
-- Финальное объединение метрик
SELECT r.race AS "Раса персонажа",
       tru.race_users AS "Зарегистрировано игроков",
       br.buyer_users AS "Количество покупателей",
       -- Доля покупателей от зарегистрированных:
       ROUND(br.buyer_users::numeric / tru.race_users, 4) AS "Доля покупателей",
       -- Доля платящих игроков среди покупателей:
       ROUND(pr.payer_users::numeric / br.buyer_users, 4) AS "Доля платящих среди покупателей",
       -- Среднее количество покупок на одного покупателя:
       ROUND(mr.total_trans::numeric / mr.unique_buyers, 4) AS "Среднее кол-во покупок",
       -- Средняя стоимость одной покупки (средний чек транзакции):
       ROUND(mr.total_amount::numeric / mr.total_trans, 4) AS "Средняя стоимость покупки",
       -- Средняя суммарная стоимость всех покупок на одного покупателя:
       ROUND(mr.total_amount::numeric / mr.unique_buyers, 4) AS "Средние суммарные траты"
FROM total_race_users AS tru
LEFT JOIN buyer_race AS br USING (race_id)
LEFT JOIN payer_race AS pr USING (race_id)
LEFT JOIN metrics_race AS mr USING (race_id)
LEFT JOIN fantasy.race AS r USING (race_id)
ORDER BY "Доля платящих среди покупателей" DESC;
