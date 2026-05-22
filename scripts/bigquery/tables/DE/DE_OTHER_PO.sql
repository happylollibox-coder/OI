-- DE_OTHER_PO: User-entered 'Other' Purchase Orders for services like Certifications, Sampling, Photography

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_OTHER_PO` (
    other_po_id STRING NOT NULL OPTIONS(description="Unique ID for the other purchase order (e.g., OPO-...)"),
    order_date DATE NOT NULL OPTIONS(description="Date the order was placed"),
    service_type STRING NOT NULL OPTIONS(description="Type of service (e.g., Certifications, Sampling, Photography)"),
    supplier_name STRING NOT NULL OPTIONS(description="Name of the supplier/vendor"),
    product_asins STRING OPTIONS(description="Comma-separated list of related ASINs"),
    total_amount FLOAT64 NOT NULL OPTIONS(description="Total cost of the service"),
    currency STRING DEFAULT 'USD' OPTIONS(description="Currency of the payment"),
    payment_status STRING DEFAULT 'PENDING' OPTIONS(description="Status of the payment (e.g., PENDING, PAID, PARTIAL)"),
    notes STRING OPTIONS(description="Any additional notes or descriptions"),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP() OPTIONS(description="Timestamp when the record was created")
)
PARTITION BY order_date
CLUSTER BY supplier_name, service_type
OPTIONS(
    description="User-entered 'Other' Purchase Orders for services like Certifications, Sampling, Photography"
);

-- Add primary key constraint after table creation to ensure it is enforced
ALTER TABLE `onyga-482313.OI.DE_OTHER_PO`
    ADD PRIMARY KEY (other_po_id) NOT ENFORCED;
