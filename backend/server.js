const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
const PORT = 3000;

app.use(cors());
app.use(bodyParser.json());

// Mock Data
const drivers = [
    { name: "John Doe", vehicle: "Toyota Prius", plate: "AB12 CDE", rating: 4.8 },
    { name: "Sarah Smith", vehicle: "Tesla Model 3", plate: "XY98 ZYW", rating: 4.9 },
    { name: "Michael Brown", vehicle: "Ford Mondeo", plate: "LM45 NOP", rating: 4.7 }
];

let currentRideStatus = "driver_assigned";

// Routes

// 1. Authentication (Mock)
app.post('/api/login', (req, res) => {
    const { email, password } = req.body;
    // Accept any login for demo
    if (email && password) {
        res.json({
            success: true,
            token: "mock_token_12345",
            user: {
                id: 1,
                firstName: "Demo",
                lastName: "User",
                email: email
            }
        });
    } else {
        res.status(400).json({ success: false, message: "Invalid credentials" });
    }
});

app.post('/api/signup', (req, res) => {
    const { email, password, firstName, lastName } = req.body;
    if (email && password && firstName && lastName) {
        res.json({
            success: true,
            token: "mock_token_67890",
            user: {
                id: 2,
                firstName,
                lastName,
                email
            }
        });
    } else {
        res.status(400).json({ success: false, message: "Missing fields" });
    }
});

// 2. Booking (Mock)
app.post('/api/book', (req, res) => {
    const { pickup, destination, vehicleType } = req.body;

    // Simulate processing delay
    setTimeout(() => {
        const randomDriver = drivers[Math.floor(Math.random() * drivers.length)];
        const otp = Math.floor(1000 + Math.random() * 9000).toString(); // 4-digit OTP
        currentRideStatus = "driver_assigned"; // Reset status for new ride

        res.json({
            success: true,
            bookingId: "book_" + Date.now(),
            status: "driver_assigned",
            otp: otp,
            driver: randomDriver,
            eta: "5 mins",
            fare: 15.50 // Static fare for demo
        });
    }, 1000);
});

// 3. Ride Status (Simulation)
let statusCallCount = 0; // Track how many times status has been called

app.get('/api/ride-status', (req, res) => {
    // Advance status based on number of calls for more predictable flow
    statusCallCount++;

    if (currentRideStatus === "driver_assigned") {
        // After 3-5 calls, move to next state
        if (statusCallCount >= 3) {
            currentRideStatus = "driver_arrived";
            statusCallCount = 0; // Reset counter
        }
    } else if (currentRideStatus === "driver_arrived") {
        if (statusCallCount >= 2) {
            currentRideStatus = "in_progress";
            statusCallCount = 0;
        }
    } else if (currentRideStatus === "in_progress") {
        if (statusCallCount >= 5) {
            currentRideStatus = "completed";
            statusCallCount = 0;
        }
    }

    res.json({
        status: currentRideStatus,
        location: {
            lat: 51.5074,
            lng: -0.1278
        }
    });
});

// Reset status endpoint for testing
app.post('/api/reset-ride', (req, res) => {
    currentRideStatus = "driver_assigned";
    res.json({ success: true, status: currentRideStatus });
});

// 4. Complete Ride & Get Fare
app.post('/api/complete-ride', (req, res) => {
    const { bookingId, rating, tip, feedback } = req.body;

    // Mock fare calculation
    const fare = {
        base: 2.50,
        distance: 8.20,
        time: 2.30,
        subtotal: 13.00,
        tip: tip || 0,
        total: 13.00 + (tip || 0)
    };

    res.json({
        success: true,
        fare: fare,
        receipt: {
            bookingId,
            date: new Date().toISOString(),
            rating,
            feedback
        }
    });
});

app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
});
