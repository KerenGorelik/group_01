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