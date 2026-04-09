export async function processStoreOrder(job: unknown): Promise<void> {
  const { data } = job as { data: { orderId: string; userId: string } };
  // TODO: Process payment, update order status, update inventory
  console.log('Processing store order', data);
}
