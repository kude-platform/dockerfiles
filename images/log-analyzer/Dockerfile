### build stage ###
FROM golang:1.14-alpine AS builder
COPY log-analyzer.go .
RUN go build -o server .

### run stage ###
FROM alpine:3.12
COPY --from=builder /go/server ./server
CMD ["./server"]