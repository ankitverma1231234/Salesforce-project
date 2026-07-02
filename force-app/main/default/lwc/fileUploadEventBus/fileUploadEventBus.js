const subscribers = [];

const subscribe = (handler) => {
    subscribers.push(handler);
};

const unsubscribe = (handler) => {
    const index = subscribers.indexOf(handler);
    if (index !== -1) {
        subscribers.splice(index, 1);
    }
};

const publish = (data) => {
    subscribers.forEach(handler => {
        try { handler(data); } catch (e) { /* ignore */ }
    });
};

export { subscribe, unsubscribe, publish };