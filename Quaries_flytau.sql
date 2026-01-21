USE flytau;
SELECT AVG(t.taken_seats) AS avg_taken_seats
FROM (
    SELECT f.Flight_number, COUNT(*) AS taken_seats
    FROM Flight f
    JOIN Seats_in_flight s
      ON f.Flight_number = s.Flight_number
     AND f.Plane_id = s.Plane_id
    WHERE f.Flight_status = 'LANDED'
      AND s.Availability = 0
    GROUP BY f.Flight_number
) AS t;



SELECT
SUM(
    CASE b.Booking_status
      WHEN 'CUSTOMER_CANCELLED' THEN fp.Price * 0.05
      ELSE fp.Price
    END
  ) AS price,
  p.Size,
  p.Manufacturer,
  c.Class_type
FROM Flight f
JOIN Booking b
  ON b.Flight_number = f.Flight_number
JOIN Seats_in_order sio
  ON sio.Booking_number = b.Booking_number
 AND sio.Plane_id = f.Plane_id
JOIN Class c
  ON c.Plane_id = sio.Plane_id
 AND sio.row_num BETWEEN c.first_row AND c.last_row
 AND sio.col_num BETWEEN c.first_col AND c.last_col
JOIN Flight_pricing fp
  ON fp.Flight_number = f.Flight_number
 AND fp.Plane_id = f.Plane_id
 AND fp.Class_type = c.Class_type
JOIN Plane p
  ON p.Plane_id = f.Plane_id
WHERE f.Flight_status IN ('LANDED', 'FULLY BOOKED', 'ACTIVE')
  AND b.Booking_status IN ('ACTIVE', 'COMPLETED', 'CUSTOMER_CANCELLED')
GROUP BY p.Size, p.Manufacturer, c.Class_type;


SELECT coalesce(SUM(CASE
                      WHEN Flying_route.Duration<=6 THEN Flying_route.Duration
		            END),0) AS sum_short_duration,
		coalesce(SUM(CASE
                      WHEN Flying_route.Duration>6 THEN Flying_route.Duration
					 END),0) AS sum_long_duration,
           Pilot.Employee_id
FROM Pilots_in_flight
     INNER JOIN 
     Flight 
     ON Flight.Flight_number = Pilots_in_flight.Flight_number
     INNER JOIN
     Flying_route
     ON Flight.Route_id = Flying_route.Route_id
     INNER JOIN
     Pilot
     ON Pilots_in_flight.Employee_id = Pilot.Employee_id
GROUP BY Pilot.Employee_id
UNION
SELECT coalesce(SUM(CASE
                     WHEN Flying_route.Duration<=6 THEN Flying_route.Duration
		            END),0) AS sum_short_duration,
		coalesce(SUM(CASE
                      WHEN Flying_route.Duration>6 THEN Flying_route.Duration
					 END),0) AS sum_long_duration,
           Steward.Employee_id
FROM Stewards_in_flight
     INNER JOIN 
     Flight 
     ON Flight.Flight_number = Stewards_in_flight.Flight_number
     INNER JOIN
     Flying_route
     ON Flight.Route_id = Flying_route.Route_id
     INNER JOIN
     Steward
     ON Stewards_in_flight.Employee_id = Steward.Employee_id
GROUP BY Steward.Employee_id;

SELECT
  DATE_FORMAT(b.Booking_date, '%Y-%m') AS ym,
  SUM(b.Booking_status IN ('CUSTOMER_CANCELLED','SYSTEM_CANCELLED')) /
  COUNT(*) AS cancellation_rate
FROM Booking b
GROUP BY ym
ORDER BY ym;

SELECT 
    gc.Plane_id,
    gc.flight_month,
    COALESCE(gc.total_executed, 0) AS total_executed,
    COALESCE(gc.total_cancelled, 0) AS total_cancelled,
    (COALESCE(ud.utilized_days, 0) / 30.0) * 100 AS utilization_pct,
    COALESCE(dr.Origin_city, 'N/A') AS Origin_city,
    COALESCE(dr.Destination_city, 'N/A') AS Destination_city
FROM(
    SELECT 
        f.Plane_id,
        DATE_FORMAT(f.Departure_date, '%Y-%m') AS flight_month,
        SUM(CASE WHEN f.Flight_status = 'LANDED' THEN 1 ELSE 0 END) AS total_executed,
        SUM(CASE WHEN f.Flight_status = 'CANCELLED' THEN 1 ELSE 0 END) AS total_cancelled
    FROM Flight AS f
    GROUP BY f.Plane_id, DATE_FORMAT(f.Departure_date, '%Y-%m')
) AS gc
LEFT JOIN
(
    SELECT 
        d.Plane_id,
        d.flight_month,
        COUNT(*) AS utilized_days
    FROM(
        SELECT DISTINCT
            x.Plane_id, x.flight_month, x.utilized_day
        FROM(
            SELECT 
                f.Plane_id,
                DATE_FORMAT(f.Departure_date, '%Y-%m') AS flight_month,
                DATE(f.Departure_date) AS utilized_day
            FROM Flight AS f
            JOIN Flying_route AS r
                ON f.Route_id = r.Route_id
            WHERE f.Flight_status = 'LANDED'

            UNION

            SELECT 
                f.Plane_id,
                DATE_FORMAT(f.Departure_date, '%Y-%m') AS flight_month,
                DATE(DATE_ADD(f.Departure_date, INTERVAL r.Duration MINUTE)) AS utilized_day
            FROM Flight AS f
            JOIN Flying_Route AS r
                ON f.Route_id = r.Route_id
            WHERE f.Flight_status = 'LANDED'
              AND DATE(DATE_ADD(f.Departure_date, INTERVAL r.Duration MINUTE)) <> DATE(f.Departure_date)
        ) AS x
    ) AS d
    GROUP BY d.Plane_id, d.flight_month
) AS ud
  ON ud.Plane_id = gc.Plane_id 
 AND ud.flight_month = gc.flight_month

LEFT JOIN
(
    SELECT 
        rc.Plane_id,
        rc.flight_month,
        rc.Origin_city,
        rc.Destination_city
    FROM(
        SELECT 
            f.Plane_id,
            DATE_FORMAT(f.Departure_date, '%Y-%m') AS flight_month,
            ao.City AS Origin_city,
            ad.City AS Destination_city,
            COUNT(*) AS route_count
        FROM Flight AS f
        JOIN Flying_route AS r
            ON f.Route_id = r.Route_id
        JOIN Airport AS ao
            ON r.Origin_airport = ao.Airport_Code
        JOIN Airport AS ad
            ON r.Destination_airport = ad.Airport_Code
        WHERE f.Flight_status = 'LANDED'
        GROUP BY f.Plane_id, DATE_FORMAT(f.Departure_date, '%Y-%m'), ao.City, ad.City
    ) AS rc
    JOIN
    (
        SELECT 
            t.Plane_id,
            t.flight_month,
            MAX(t.route_count) AS max_cnt
        FROM(
            SELECT 
                f2.Plane_id,
                DATE_FORMAT(f2.Departure_date, '%Y-%m') AS flight_month,
                ao2.City AS Origin_city,
                ad2.City AS Destination_city,
                COUNT(*) AS route_count
            FROM Flight AS f2
            JOIN Flying_Route AS r2
                ON f2.Route_id = r2.Route_id
            JOIN Airport AS ao2
                ON r2.Origin_airport = ao2.Airport_Code
            JOIN Airport AS ad2
                ON r2.Destination_airport = ad2.Airport_Code
            WHERE f2.Flight_status = 'LANDED'
            GROUP BY f2.Plane_id, DATE_FORMAT(f2.Departure_date, '%Y-%m'), ao2.City, ad2.City
        ) AS t
        GROUP BY t.Plane_id, t.flight_month
    ) AS mx
      ON mx.Plane_id = rc.Plane_id 
     AND mx.flight_month = rc.flight_month 
     AND mx.max_cnt = rc.route_count
) AS dr
  ON dr.Plane_id = gc.Plane_id 
	AND dr.flight_month = gc.flight_month
ORDER BY gc.Plane_id, gc.flight_month;



