# Go Testing Techniques Reference

> Code examples and configurations for Go testing. Concepts assumed known.

## Go (testing + testify)

```go
func TestOrderService_Cancel(t *testing.T) {
    // Arrange
    mockRepo := new(MockOrderRepository)
    mockPublisher := new(MockEventPublisher)
    sut := NewOrderService(mockRepo, mockPublisher)

    order := fixtures.ConfirmedOrder()
    mockRepo.On("FindByID", mock.Anything, order.ID).Return(order, nil)
    mockPublisher.On("Publish", mock.Anything, mock.AnythingOfType("*events.OrderCancelledEvent")).Return(nil)

    // Act
    result, err := sut.Cancel(context.Background(), order.ID, CancelReasonUserRequest)

    // Assert
    assert.NoError(t, err)
    assert.Equal(t, OrderStatusCancelled, result.Status)
    mockRepo.AssertExpectations(t)
    mockPublisher.AssertExpectations(t)
}
```

### testify Assertions

```go
// Basic assertions
assert.Equal(t, expected, actual)
assert.NotEqual(t, expected, actual)
assert.Nil(t, obj)
assert.NotNil(t, obj)
assert.True(t, value)
assert.False(t, value)
assert.Error(t, err)
assert.NoError(t, err)
assert.ErrorIs(t, err, ErrNotFound)
assert.ErrorContains(t, err, "not found")

// Collection assertions
assert.Len(t, slice, 3)
assert.Contains(t, slice, element)
assert.Empty(t, slice)
assert.NotEmpty(t, slice)
assert.ElementsMatch(t, expected, actual) // order-independent

// require (fails immediately)
require.NoError(t, err) // stops test on failure
```

### testify Mock

```go
// Mock definition
type MockOrderRepository struct {
    mock.Mock
}

func (m *MockOrderRepository) FindByID(ctx context.Context, id string) (*Order, error) {
    args := m.Called(ctx, id)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*Order), args.Error(1)
}

// Mock setup
mockRepo.On("FindByID", mock.Anything, "order-123").Return(&Order{ID: "order-123"}, nil)
mockRepo.On("FindByID", mock.Anything, "not-found").Return(nil, ErrNotFound)
mockRepo.On("Save", mock.Anything, mock.AnythingOfType("*Order")).Return(nil)

// Verification
mockRepo.AssertExpectations(t)
mockRepo.AssertCalled(t, "FindByID", mock.Anything, "order-123")
mockRepo.AssertNumberOfCalls(t, "Save", 1)
```

## Table-Driven Tests

```go
func TestOrder_Validate(t *testing.T) {
    tests := []struct {
        name    string
        order   Order
        wantErr bool
        errMsg  string
    }{
        {
            name:    "valid order",
            order:   Order{ID: "123", Amount: 100, Currency: "USD"},
            wantErr: false,
        },
        {
            name:    "missing ID",
            order:   Order{Amount: 100, Currency: "USD"},
            wantErr: true,
            errMsg:  "id is required",
        },
        {
            name:    "negative amount",
            order:   Order{ID: "123", Amount: -100, Currency: "USD"},
            wantErr: true,
            errMsg:  "amount must be positive",
        },
        {
            name:    "invalid currency",
            order:   Order{ID: "123", Amount: 100, Currency: "INVALID"},
            wantErr: true,
            errMsg:  "invalid currency",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := tt.order.Validate()

            if tt.wantErr {
                assert.Error(t, err)
                assert.Contains(t, err.Error(), tt.errMsg)
            } else {
                assert.NoError(t, err)
            }
        })
    }
}
```

## Parallel Tests

```go
func TestOrderService_Concurrent(t *testing.T) {
    t.Parallel() // Mark test as parallelizable

    tests := []struct {
        name string
        // ...
    }{
        // test cases
    }

    for _, tt := range tests {
        tt := tt // Capture range variable (required for parallel subtests)
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel() // Run subtest in parallel
            // test logic
        })
    }
}
```

## Ginkgo/Gomega (BDD Style)

```go
var _ = Describe("OrderService", func() {
    var (
        mockRepo      *MockOrderRepository
        mockPublisher *MockEventPublisher
        sut           *OrderService
    )

    BeforeEach(func() {
        mockRepo = new(MockOrderRepository)
        mockPublisher = new(MockEventPublisher)
        sut = NewOrderService(mockRepo, mockPublisher)
    })

    Describe("Cancel", func() {
        Context("when order is confirmed", func() {
            var order *Order

            BeforeEach(func() {
                order = fixtures.ConfirmedOrder()
                mockRepo.On("FindByID", mock.Anything, order.ID).Return(order, nil)
                mockPublisher.On("Publish", mock.Anything, mock.Anything).Return(nil)
            })

            It("should change status to cancelled", func() {
                result, err := sut.Cancel(context.Background(), order.ID, CancelReasonUserRequest)

                Expect(err).NotTo(HaveOccurred())
                Expect(result.Status).To(Equal(OrderStatusCancelled))
            })

            It("should publish cancel event", func() {
                _, _ = sut.Cancel(context.Background(), order.ID, CancelReasonUserRequest)

                mockPublisher.AssertCalled(GinkgoT(), "Publish", mock.Anything, mock.AnythingOfType("*events.OrderCancelledEvent"))
            })
        })

        Context("when order is already cancelled", func() {
            BeforeEach(func() {
                order := fixtures.CancelledOrder()
                mockRepo.On("FindByID", mock.Anything, order.ID).Return(order, nil)
            })

            It("should return error", func() {
                _, err := sut.Cancel(context.Background(), "cancelled-order", CancelReasonUserRequest)

                Expect(err).To(MatchError(ErrAlreadyCancelled))
            })
        })
    })
})
```

### Gomega Matchers

```go
// Equality
Expect(actual).To(Equal(expected))
Expect(actual).To(BeEquivalentTo(expected))
Expect(actual).To(BeIdenticalTo(expected))

// Nil/Empty
Expect(obj).To(BeNil())
Expect(slice).To(BeEmpty())
Expect(slice).To(HaveLen(3))

// Boolean
Expect(value).To(BeTrue())
Expect(value).To(BeFalse())

// Errors
Expect(err).To(HaveOccurred())
Expect(err).NotTo(HaveOccurred())
Expect(err).To(MatchError("error message"))
Expect(err).To(MatchError(ErrNotFound))

// Collections
Expect(slice).To(ContainElement(item))
Expect(slice).To(ContainElements(item1, item2))
Expect(slice).To(ConsistOf(item1, item2, item3)) // exact match, any order

// Strings
Expect(str).To(ContainSubstring("partial"))
Expect(str).To(HavePrefix("start"))
Expect(str).To(HaveSuffix("end"))
Expect(str).To(MatchRegexp(`\d+`))

// Numeric
Expect(num).To(BeNumerically(">", 10))
Expect(num).To(BeNumerically("~", 10, 0.1)) // approximately
```

## mockgen (Interface Mocking)

```go
//go:generate mockgen -source=repository.go -destination=mock_repository.go -package=order

type OrderRepository interface {
    FindByID(ctx context.Context, id string) (*Order, error)
    Save(ctx context.Context, order *Order) error
    Delete(ctx context.Context, id string) error
}
```

Generated mock usage:
```go
func TestWithMockgen(t *testing.T) {
    ctrl := gomock.NewController(t)
    defer ctrl.Finish()

    mockRepo := NewMockOrderRepository(ctrl)
    mockRepo.EXPECT().FindByID(gomock.Any(), "order-123").Return(&Order{ID: "order-123"}, nil)
    mockRepo.EXPECT().Save(gomock.Any(), gomock.Any()).Return(nil)

    sut := NewOrderService(mockRepo)
    // test logic
}
```

## HTTP Handler Testing

```go
func TestOrderHandler_Create(t *testing.T) {
    mockService := new(MockOrderService)
    handler := NewOrderHandler(mockService)

    // Setup expectation
    mockService.On("Create", mock.Anything, mock.AnythingOfType("*CreateOrderRequest")).
        Return(&Order{ID: "new-order"}, nil)

    // Create request
    body := `{"amount": 100, "currency": "USD"}`
    req := httptest.NewRequest(http.MethodPost, "/orders", strings.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    rec := httptest.NewRecorder()

    // Execute
    handler.Create(rec, req)

    // Assert
    assert.Equal(t, http.StatusCreated, rec.Code)

    var response Order
    err := json.NewDecoder(rec.Body).Decode(&response)
    assert.NoError(t, err)
    assert.Equal(t, "new-order", response.ID)
}
```

## Gin Handler Testing

```go
func TestOrderHandler_Create_Gin(t *testing.T) {
    gin.SetMode(gin.TestMode)

    mockService := new(MockOrderService)
    handler := NewOrderHandler(mockService)

    mockService.On("Create", mock.Anything, mock.AnythingOfType("*CreateOrderRequest")).
        Return(&Order{ID: "new-order"}, nil)

    router := gin.New()
    router.POST("/orders", handler.Create)

    body := `{"amount": 100, "currency": "USD"}`
    req := httptest.NewRequest(http.MethodPost, "/orders", strings.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    rec := httptest.NewRecorder()

    router.ServeHTTP(rec, req)

    assert.Equal(t, http.StatusCreated, rec.Code)
}
```

## Test Fixtures

```go
// fixtures/order.go
package fixtures

func ConfirmedOrder() *Order {
    return &Order{
        ID:        "order-123",
        Status:    OrderStatusConfirmed,
        Amount:    100,
        Currency:  "USD",
        CreatedAt: time.Now().Add(-time.Hour),
    }
}

func CancelledOrder() *Order {
    order := ConfirmedOrder()
    order.Status = OrderStatusCancelled
    order.CancelledAt = ptr(time.Now())
    return order
}

func OrderWithItems(items ...Item) *Order {
    order := ConfirmedOrder()
    order.Items = items
    return order
}

// Helper
func ptr[T any](v T) *T {
    return &v
}
```

## Test Configuration

### go.mod test dependencies

```
require (
    github.com/stretchr/testify v1.9.0
    github.com/golang/mock v1.6.0
    github.com/onsi/ginkgo/v2 v2.17.0
    github.com/onsi/gomega v1.32.0
)
```

### Running tests

```bash
# Run all tests
go test ./...

# Run with verbose output
go test -v ./...

# Run with coverage
go test -cover ./...

# Generate coverage report
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html

# Run specific test
go test -run TestOrderService_Cancel ./...

# Run with race detector
go test -race ./...

# Run parallel with limit
go test -parallel 4 ./...

# Timeout
go test -timeout 30s ./...
```

## Framework Selection Guide

| Scenario | Recommendation |
|----------|----------------|
| Simple unit tests | `testing` + `testify/assert` |
| Interface mocking | `testify/mock` or `mockgen` |
| BDD-style tests | Ginkgo + Gomega |
| Large test suites | Ginkgo (better organization) |
| Property-based tests | `gopter` or `rapid` |
| Integration tests | `testcontainers-go` |
