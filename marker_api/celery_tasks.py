from celery import Task
from marker_api.celery_worker import celery_app
from marker.config.parser import ConfigParser
from marker.output import text_from_rendered
from marker.converters.pdf import PdfConverter
from marker.models import create_model_dict
from marker.settings import settings
import io
import os
import time
import logging
from marker_api.utils import process_image_to_base64
from celery.signals import worker_process_init
import base64

logger = logging.getLogger(__name__)

model_list = None


@worker_process_init.connect
def initialize_models(**kwargs):
    global model_list
    if not model_list:
        model_list = create_model_dict()
        print("Models loaded at worker startup")


def convert_single_pdf_new_api(pdf_file, model_list):
    """
    Convert a single PDF using the new marker 1.7.4 API.
    
    Args:
        pdf_file: BytesIO object containing PDF data
        model_list: The loaded model dictionary
        
    Returns:
        tuple: (markdown_text, images, metadata)
    """
    # Save PDF bytes to a temporary file since PdfConverter expects a file path
    temp_pdf_path = f"/tmp/temp_pdf_{int(time.time())}.pdf"
    try:
        with open(temp_pdf_path, "wb") as f:
            pdf_file.seek(0)
            f.write(pdf_file.read())
        
        # Create configuration using ConfigParser
        options = {
            "filepath": temp_pdf_path,
            "output_format": "markdown",
            "force_ocr": False,
            "paginate_output": False
        }
        config_parser = ConfigParser(options)
        config_dict = config_parser.generate_config_dict()
        config_dict["pdftext_workers"] = 1
        
        # Create converter
        converter = PdfConverter(
            config=config_dict,
            artifact_dict=model_list,
            processor_list=config_parser.get_processors(),
            renderer=config_parser.get_renderer(),
            llm_service=config_parser.get_llm_service(),
        )
        
        # Convert PDF
        rendered = converter(temp_pdf_path)
        markdown_text, _, images = text_from_rendered(rendered)
        metadata = rendered.metadata
        
        return markdown_text, images, metadata
        
    finally:
        # Clean up temporary file
        if os.path.exists(temp_pdf_path):
            os.remove(temp_pdf_path)


class PDFConversionTask(Task):
    abstract = True

    def __init__(self):
        super().__init__()

    def __call__(self, *args, **kwargs):
        # Use the global model_list initialized at worker startup
        return self.run(*args, **kwargs)


@celery_app.task(
    ignore_result=False, bind=True, base=PDFConversionTask, name="convert_pdf"
)
def convert_pdf_to_markdown(self, filename, pdf_content):
    pdf_file = io.BytesIO(pdf_content)
    markdown_text, images, metadata = convert_single_pdf_new_api(pdf_file, model_list)
    image_data = {}
    for i, (img_filename, image) in enumerate(images.items()):
        logger.debug(f"Processing image {img_filename}")
        
        # Convert image to base64 using settings
        byte_stream = io.BytesIO()
        image.save(byte_stream, format=settings.OUTPUT_IMAGE_FORMAT)
        image_base64 = base64.b64encode(byte_stream.getvalue()).decode(settings.OUTPUT_ENCODING)
        image_data[img_filename] = image_base64

    return {
        "filename": filename,
        "markdown": markdown_text,
        "metadata": metadata,
        "images": image_data,
        "status": "ok",
    }


# @celery_app.task(
#     ignore_result=False, bind=True, base=PDFConversionTask, name="process_batch"
# )
# def process_batch(self, batch_data):
#     results = []
#     for filename, pdf_content in batch_data:
#         try:
#             result = convert_pdf_to_markdown(filename, pdf_content)
#             results.append(result)
#         except Exception as e:
#             logger.error(f"Error processing {filename}: {str(e)}")
#             results.append({"filename": filename, "status": "Error", "error": str(e)})
#     return results


@celery_app.task(
    ignore_result=False, bind=True, base=PDFConversionTask, name="process_batch"
)
def process_batch(self, batch_data):
    results = []
    total = len(batch_data)
    for i, (filename, pdf_content) in enumerate(batch_data, start=1):
        try:
            result = convert_pdf_to_markdown(filename, pdf_content)
            results.append(result)
        except Exception as e:
            logger.error(f"Error processing {filename}: {str(e)}")
            results.append({"filename": filename, "status": "Error", "error": str(e)})

        # Update progress
        self.update_state(state="PROGRESS", meta={"current": i, "total": total})

    return results
