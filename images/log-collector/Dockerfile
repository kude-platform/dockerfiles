### build stage ###
FROM golang:1.22-alpine AS builder
COPY log-collector.go .
COPY go.mod .
RUN go build -o server .

### run stage ###
FROM alpine:3.12
COPY --from=builder /go/server ./server
CMD ["./server"]