
-- Quary 1 --
USE flytau2;

SELECT AVG(occ_pct) AS avg_occupancy_pct
FROM (
    SELECT
        f.Flight_number,
        100.0 * SUM(s.Availability = 0) / COUNT(*) AS occ_pct
    FROM Flight f
    JOIN Seats_in_flight s
      ON s.Flight_number = f.Flight_number
     AND s.Plane_id      = f.Plane_id
    WHERE f.Flight_status = 'LANDED'
    GROUP BY f.Flight_number
) t;


-- Quary 2 --

SELECT
    COALESCE(SUM(
        CASE
            WHEN sio.Booking_number IS NULL THEN 0
            WHEN b.Booking_status = 'CUSTOMER_CANCELLED' THEN fp.Price * 0.05
            ELSE fp.Price
        END
    ), 0) AS price,
    p.Size,
    p.Manufacturer,
    c.Class_type
FROM Flight f
JOIN Plane p
  ON p.Plane_id = f.Plane_id
JOIN Class c
  ON c.Plane_id = f.Plane_id

-- מחיר למחלקה בטיסה (מכווץ כדי למנוע הכפלות אם יש כמה רשומות תמחור)
LEFT JOIN (
    SELECT Flight_number, Plane_id, Class_type, MAX(Price) AS Price
    FROM Flight_pricing
    GROUP BY Flight_number, Plane_id, Class_type
) fp
  ON fp.Flight_number = f.Flight_number
 AND fp.Plane_id     = f.Plane_id
 AND fp.Class_type   = c.Class_type

-- הזמנות: LEFT JOIN כדי לא להפיל טיסות בלי הזמנות
LEFT JOIN Booking b
  ON b.Flight_number = f.Flight_number
 AND b.Booking_status IN ('ACTIVE', 'COMPLETED', 'CUSTOMER_CANCELLED')

-- מושבים שנמכרו: LEFT JOIN כדי לא להפיל טיסות/מחלקות בלי מכירות
LEFT JOIN Seats_in_order sio
  ON sio.Booking_number = b.Booking_number
 AND sio.Plane_id       = f.Plane_id
 AND sio.row_num BETWEEN c.first_row AND c.last_row
 AND sio.col_num BETWEEN c.first_col AND c.last_col

WHERE f.Flight_status IN ('LANDED', 'FULLY BOOKED', 'ACTIVE')
GROUP BY p.Size, p.Manufacturer, c.Class_type;

-- Quary 3 --
SELECT
    p.Employee_id,
    'PILOT' AS role,
    COALESCE(SUM(CASE
        WHEN fr.Duration <= 360 THEN fr.Duration / 60.0
        ELSE 0
    END), 0) AS sum_short_duration,
    COALESCE(SUM(CASE
        WHEN fr.Duration > 360 THEN fr.Duration / 60.0
        ELSE 0
    END), 0) AS sum_long_duration
FROM Pilot p
LEFT JOIN Pilots_in_flight pif
    ON pif.Employee_id = p.Employee_id
LEFT JOIN Flight f
    ON f.Flight_number = pif.Flight_number
   AND f.Flight_status = 'LANDED'
LEFT JOIN Flying_route fr
    ON fr.Route_id = f.Route_id
GROUP BY p.Employee_id

UNION ALL

SELECT
    s.Employee_id,
    'STEWARD' AS role,
    COALESCE(SUM(CASE
        WHEN fr.Duration <= 360 THEN fr.Duration / 60.0
        ELSE 0
    END), 0) AS sum_short_duration,
    COALESCE(SUM(CASE
        WHEN fr.Duration > 360 THEN fr.Duration / 60.0
        ELSE 0
    END), 0) AS sum_long_duration
FROM Steward s
LEFT JOIN Stewards_in_flight sif
    ON sif.Employee_id = s.Employee_id
LEFT JOIN Flight f
    ON f.Flight_number = sif.Flight_number
   AND f.Flight_status = 'LANDED'
LEFT JOIN Flying_route fr
    ON fr.Route_id = f.Route_id
GROUP BY s.Employee_id;

-- Quary 4 --
SELECT
  DATE_FORMAT(b.Booking_date, '%Y-%m') AS ym,
  SUM(b.Booking_status IN ('CUSTOMER_CANCELLED','SYSTEM_CANCELLED')) /
  COUNT(*) AS cancellation_rate
FROM Booking b
GROUP BY ym
ORDER BY ym;

-- Quary 5 --
SELECT
    m.Plane_id,
    m.ym,
    COALESCE(ms.performed_cnt, 0)  AS performed_cnt,
    COALESCE(ms.cancelled_cnt, 0)  AS cancelled_cnt,
    (COALESCE(u.utilized_days, 0) / 30.0) * 100        AS utilization_pct,
    dr.dominant_routes
FROM (
    SELECT
        x.Plane_id,
        x.mi,
        CONCAT(2000 + (x.mi DIV 12), '-', LPAD((x.mi MOD 12) + 1, 2, '0')) AS ym
    FROM (
        SELECT
            f.Plane_id,
            FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS mi
        FROM Flight f
        GROUP BY f.Plane_id,
                 FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30)

        UNION

        SELECT
            a.Plane_id,
            a.arr_mi AS mi
        FROM (
            SELECT
                f.Plane_id,
                FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS dep_mi,
                FLOOR((
                    TO_DAYS(DATE(DATE_ADD(TIMESTAMP(f.Departure_date, f.Departure_time), INTERVAL r.Duration MINUTE)))
                    - TO_DAYS('2000-01-01')
                ) / 30) AS arr_mi
            FROM Flight f
            JOIN Flying_route r ON r.Route_id = f.Route_id
            WHERE f.Flight_status IN ('LANDED','ACTIVE','FULLY BOOKED')
        ) a
        WHERE a.arr_mi <> a.dep_mi
        GROUP BY a.Plane_id, a.arr_mi
    ) x
) AS m

LEFT JOIN (
    SELECT
        f.Plane_id,
        FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS mi,
        SUM(f.Flight_status = 'LANDED')     AS performed_cnt,
        SUM(f.Flight_status = 'CANCELLED')  AS cancelled_cnt
    FROM Flight f
    GROUP BY
        f.Plane_id,
        FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30)
) AS ms
  ON ms.Plane_id = m.Plane_id AND ms.mi = m.mi

LEFT JOIN (
    SELECT
        z.Plane_id,
        z.mi,
        COUNT(DISTINCT z.utilized_day) AS utilized_days
    FROM (
        SELECT
            f.Plane_id,
            FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS mi,
            f.Departure_date AS utilized_day
        FROM Flight f
        WHERE f.Flight_status IN ('LANDED','ACTIVE','FULLY BOOKED')

        UNION ALL

        SELECT
            t.Plane_id,
            FLOOR((TO_DAYS(DATE(t.arr_ts)) - TO_DAYS('2000-01-01')) / 30) AS mi,
            DATE(t.arr_ts) AS utilized_day
        FROM (
            SELECT
                f.Plane_id,
                TIMESTAMP(f.Departure_date, f.Departure_time) AS dep_ts,
                DATE_ADD(TIMESTAMP(f.Departure_date, f.Departure_time), INTERVAL r.Duration MINUTE) AS arr_ts
            FROM Flight f
            JOIN Flying_route r ON r.Route_id = f.Route_id
            WHERE f.Flight_status IN ('LANDED','ACTIVE','FULLY BOOKED')
        ) t
        WHERE DATE(t.arr_ts) <> DATE(t.dep_ts)
    ) z
    GROUP BY z.Plane_id, z.mi
) AS u
  ON u.Plane_id = m.Plane_id AND u.mi = m.mi

LEFT JOIN (
    SELECT
        c.Plane_id,
        c.mi,
        GROUP_CONCAT(
            CONCAT(c.Origin_airport, ' -> ', c.Destination_airport)
            ORDER BY c.Origin_airport, c.Destination_airport
            SEPARATOR ' | '
        ) AS dominant_routes
    FROM (
        SELECT
            fm.Plane_id,
            fm.mi,
            r.Origin_airport,
            r.Destination_airport,
            COUNT(*) AS cnt
        FROM (
            SELECT
                f.Plane_id,
                f.Route_id,
                FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS mi,
                FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS dep_mi,
                FLOOR((
                    TO_DAYS(DATE(DATE_ADD(TIMESTAMP(f.Departure_date, f.Departure_time), INTERVAL r.Duration MINUTE)))
                    - TO_DAYS('2000-01-01')
                ) / 30) AS arr_mi
            FROM Flight f
            JOIN Flying_route r ON r.Route_id = f.Route_id
            WHERE f.Flight_status IN ('LANDED','ACTIVE','FULLY BOOKED')

            UNION ALL

            SELECT
                f.Plane_id,
                f.Route_id,
                FLOOR((
                    TO_DAYS(DATE(DATE_ADD(TIMESTAMP(f.Departure_date, f.Departure_time), INTERVAL r.Duration MINUTE)))
                    - TO_DAYS('2000-01-01')
                ) / 30) AS mi,
                FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS dep_mi,
                FLOOR((
                    TO_DAYS(DATE(DATE_ADD(TIMESTAMP(f.Departure_date, f.Departure_time), INTERVAL r.Duration MINUTE)))
                    - TO_DAYS('2000-01-01')
                ) / 30) AS arr_mi
            FROM Flight f
            JOIN Flying_route r ON r.Route_id = f.Route_id
            WHERE f.Flight_status IN ('LANDED','ACTIVE','FULLY BOOKED')
        ) fm
        JOIN Flying_route r ON r.Route_id = fm.Route_id
        WHERE fm.arr_mi = fm.dep_mi OR fm.mi = fm.arr_mi
        GROUP BY fm.Plane_id, fm.mi, r.Origin_airport, r.Destination_airport
    ) c
    JOIN (
        SELECT Plane_id, mi, MAX(cnt) AS max_cnt
        FROM (
            SELECT
                fm.Plane_id,
                fm.mi,
                r.Origin_airport,
                r.Destination_airport,
                COUNT(*) AS cnt
            FROM (
                SELECT
                    f.Plane_id,
                    f.Route_id,
                    FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS mi,
                    FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS dep_mi,
                    FLOOR((
                        TO_DAYS(DATE(DATE_ADD(TIMESTAMP(f.Departure_date, f.Departure_time), INTERVAL r.Duration MINUTE)))
                        - TO_DAYS('2000-01-01')
                    ) / 30) AS arr_mi
                FROM Flight f
                JOIN Flying_route r ON r.Route_id = f.Route_id
                WHERE f.Flight_status IN ('LANDED','ACTIVE','FULLY BOOKED')

                UNION ALL

                SELECT
                    f.Plane_id,
                    f.Route_id,
                    FLOOR((
                        TO_DAYS(DATE(DATE_ADD(TIMESTAMP(f.Departure_date, f.Departure_time), INTERVAL r.Duration MINUTE)))
                        - TO_DAYS('2000-01-01')
                    ) / 30) AS mi,
                    FLOOR((TO_DAYS(f.Departure_date) - TO_DAYS('2000-01-01')) / 30) AS dep_mi,
                    FLOOR((
                        TO_DAYS(DATE(DATE_ADD(TIMESTAMP(f.Departure_date, f.Departure_time), INTERVAL r.Duration MINUTE)))
                        - TO_DAYS('2000-01-01')
                    ) / 30) AS arr_mi
                FROM Flight f
                JOIN Flying_route r ON r.Route_id = f.Route_id
                WHERE f.Flight_status IN ('LANDED','ACTIVE','FULLY BOOKED')
            ) fm
            JOIN Flying_route r ON r.Route_id = fm.Route_id
            WHERE fm.arr_mi = fm.dep_mi OR fm.mi = fm.arr_mi
            GROUP BY fm.Plane_id, fm.mi, r.Origin_airport, r.Destination_airport
        ) t
        GROUP BY Plane_id, mi
    ) mx
      ON mx.Plane_id = c.Plane_id AND mx.mi = c.mi AND mx.max_cnt = c.cnt
    GROUP BY c.Plane_id, c.mi
) AS dr
  ON dr.Plane_id = m.Plane_id AND dr.mi = m.mi

ORDER BY m.Plane_id, m.ym;



