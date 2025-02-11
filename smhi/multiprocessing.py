import multiprocessing as mp
from multiprocessing.shared_memory import SharedMemory
import os
import pickle
from alive_progress import alive_bar
from database.base import get_engine


class BaseWorker(mp.Process):
    """
    Base class for worker processes.
    Provides database access and queue-based processing.
    """
    def __init__(self, job_queue, progress_counter):
        super().__init__()
        self.job_queue = job_queue
        self.progress_counter = progress_counter
        self.engine = None

    def process_job(self, job):
        """
        Override this method in subclasses to define worker logic.
        """
        raise NotImplementedError("Subclasses must implement this method!")

    def run(self):
        """
        Process jobs from the queue until a sentinel (None) is received.
        """
        self.engine = get_engine()  # Get a database engine for this worker
        while True:
            job = self.job_queue.get()
            if job is None:  # Sentinel value to terminate worker
                self.job_queue.task_done()
                self.engine.dispose()
                break
            try:
                self.process_job(job)
                with self.progress_counter.get_lock():
                    self.progress_counter.value += 1  # Increment progress
            except Exception as e:
                print(f"Error processing job {job}: {e}")
                self.job_queue.put(job)  # Re-add the job to the queue


class BaseManager:
    """
    Base class for managers to handle job creation, worker management, and progress tracking.
    """
    def __init__(self, engine, title, num_workers=int(os.getenv("CORES"))):
        self.engine = engine
        self.manager = mp.Manager()
        self.title = title
        self.num_workers = num_workers
        self.job_queue = self.manager.Queue()
        self.workers = []
        self.progress_counter = mp.Value('i', 0)  # Shared progress counter
        self.total_jobs = 0  # Total number of jobs to track progress

    def create_jobs(self):
        """
        Override this method to populate the job queue.
        """
        raise NotImplementedError("Subclasses must implement this method!")

    def start_workers(self, worker_class, *args):
        """
        Start workers using the specified worker class.
        """
        for _ in range(self.num_workers):
            worker = worker_class(self.job_queue, self.progress_counter, *args)
            self.workers.append(worker)
            worker.start()

    def stop_workers(self):
        """
        Stop all workers by adding sentinel values to the queue.
        """
        for _ in range(self.num_workers):
            self.job_queue.put(None)
        for worker in self.workers:
            worker.join()

    def run(self, worker_class, *args):
        """
        Main method to execute the manager workflow.
        """
        self.create_jobs()  # Populate the job queue
        
        if self.total_jobs == 0:
            print("No jobs to process.")
            return

        # Start workers
        self.start_workers(worker_class, *args)

        # Display progress bar
        with alive_bar(self.total_jobs, title=self.title, bar="filling") as bar:
            while self.progress_counter.value < self.total_jobs:
                bar(self.progress_counter.value - bar.current)
            bar(self.total_jobs - bar.current)

        # Stop workers
        self.stop_workers()


def serialize_to_shared_memory(data, shm_name=None):
    """
    Serialize data to shared memory and return the SharedMemory object and name.
    
    Args:
        data: The data to serialize (e.g., Pandas DataFrame, tuple of NumPy arrays).
        shm_name: Optional shared memory name (default: None).
    
    Returns:
        Tuple of (SharedMemory object, shared memory name).
    """
    data_bytes = pickle.dumps(data)  # Serialize data
    shm = SharedMemory(create=True, size=len(data_bytes), name=shm_name)
    shm.buf[:len(data_bytes)] = data_bytes  # Copy serialized data to shared memory
    return shm, shm.name


def deserialize_from_shared_memory(shm_name):
    """
    Deserialize data from shared memory.
    
    Args:
        shm_name: The name of the shared memory segment to read from.
    
    Returns:
        The deserialized data.
    """
    shm = SharedMemory(name=shm_name)
    try:
        data_bytes = bytes(shm.buf[:])  # Read data from shared memory
        data = pickle.loads(data_bytes)  # Deserialize data
    finally:
        shm.close()  # Detach from shared memory
    return data
