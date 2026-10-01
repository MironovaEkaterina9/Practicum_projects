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
		ROUND((payer_users::numeric / total_users) * 100, 2)  AS payers_pct
FROM (SELECT COUNT(id) AS total_users,
		(SELECT COUNT(id) FROM fantasy.users WHERE payer = 1) AS payer_users
FROM fantasy.users) AS all_users;  

-- 1.2. Расчет конверсии в платящего игрока в разрезе рас персонажей:

SELECT race,
		COUNT(id) AS total_users,
		SUM(payer) AS payer_users,
		ROUND((SUM(payer)::numeric / COUNT(id)) * 100, 2) AS race_payers_pct
FROM fantasy.users AS u
LEFT JOIN fantasy.race AS r USING (race_id)
GROUP BY race
ORDER BY race_payers_pct DESC;

-- ----------------------------------------------------------------------------
-- Задача 2. Исследование внутриигровых покупок и эпических предметов
-- ----------------------------------------------------------------------------

-- 2.1. Сравнительный анализ описательной статистики (с нулевыми покупками и без):

-- Абсолютное и относительное кол-во нулевых покупок
SELECT 
    COUNT(CASE WHEN amount = 0 THEN 1 END) AS zero_amount_count,
    ROUND(COUNT(CASE WHEN amount = 0 THEN 1 END) * 100.0 / COUNT(*), 2) AS zero_amount_pct
FROM fantasy.events;

-- Сравнительный анализ описательной статистики (с нулевыми покупками и без)
SELECT 'with zero amount' AS category,
		COUNT(amount) AS total_amount,
		SUM(amount) AS sum_amount,
		MIN(amount) AS min_amount,
		MAX(amount) AS max_amount,
		AVG(amount) AS avg_amount,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median,
		STDDEV(amount) AS stand_dev
FROM fantasy.events
UNION ALL
SELECT 'without zero amount' AS category,
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
		COUNT(*) AS total_zero_amount,
		COUNT(*)::float / (SELECT COUNT(*) FROM fantasy.events) * 100 AS zero_amount_pct
FROM fantasy.events AS e
LEFT JOIN fantasy.users AS u USING (id)
LEFT JOIN fantasy.race AS r USING (race_id)
WHERE amount = 0
GROUP BY race, item_code
ORDER BY total_zero_amount DESC;

-- 2.3: Формирование рейтинга популярности и востребованности эпических предметов (исключая нулевые покупки):

WITH
-- Считаем долю уникальных покупателей для каждого предмета
item_buyers AS (
	SELECT DISTINCT item_code AS unique_item,
			CAST (COUNT (DISTINCT id) AS float) / (SELECT COUNT (DISTINCT id) FROM fantasy.events WHERE amount > 0) AS share_item_buyers	
	FROM fantasy.events AS e
	WHERE amount > 0
	GROUP BY item_code
			)
	
SELECT poi.unique_item,
		i.game_items AS item_name,
		poi.item_sales,
		ROUND(poi.item_sales::numeric / poi.total_transaction * 100, 2) AS item_sales_pct,
		ROUND(ib.share_item_buyers::numeric * 100, 2) AS item_buyers_pct
FROM (SELECT DISTINCT item_code AS unique_item,
		COUNT (transaction_id) OVER (PARTITION BY item_code) AS item_sales,
		COUNT (transaction_id) OVER () AS total_transaction
	  FROM fantasy.events
	  WHERE amount > 0) AS poi
LEFT JOIN fantasy.items AS i ON i.item_code = poi.unique_item
INNER JOIN item_buyers AS ib ON ib.unique_item = poi.unique_item
ORDER BY item_buyers_pct DESC
LIMIT 10;

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
SELECT r.race,
       tru.race_users,
       br.buyer_users,
       -- Доля покупателей от зарегистрированных:
       ROUND(br.buyer_users::numeric / tru.race_users * 100, 2) AS buyer_users_pct,
       -- Доля платящих игроков среди покупателей:
       ROUND(pr.payer_users::numeric / br.buyer_users * 100, 2) AS payer_buyer_pct,
       -- Среднее количество покупок на одного покупателя:
       ROUND(mr.total_trans::numeric / mr.unique_buyers, 2) AS purchases_per_buyer,
       -- Средняя стоимость одной покупки (средний чек транзакции):
       ROUND(mr.total_amount::numeric / mr.total_trans, 2) AS avg_order_value,
       -- Средняя суммарная стоимость всех покупок на одного покупателя:
       ROUND(mr.total_amount::numeric / mr.unique_buyers, 2) AS avg_revenue_per_buyer
FROM total_race_users AS tru
LEFT JOIN buyer_race AS br USING (race_id)
LEFT JOIN payer_race AS pr USING (race_id)
LEFT JOIN metrics_race AS mr USING (race_id)
LEFT JOIN fantasy.race AS r USING (race_id)
ORDER BY payer_buyer_pct DESC;
