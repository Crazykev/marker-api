import os
import time
import base64
import io
from marker.config.parser import ConfigParser
from marker.output import text_from_rendered
from marker.converters.pdf import PdfConverter
from marker.logger import configure_logging
from marker.settings import settings
import logging

# Initialize logging
configure_logging()
logger = logging.getLogger(__name__)


# Function to parse PDF and return markdown, metadata, and image data
def parse_pdf_and_return_markdown(pdf_file: bytes, extract_images: bool, model_list):
    """
    Function to parse a PDF and extract text and images using new marker 1.7.4 API.

    Args:
    pdf_file (bytes): The content of the PDF file.
    extract_images (bool): Whether to extract images or not.
    model_list: The loaded model dictionary.

    Returns
    tuple: A tuple containing the full text, metadata, and image data (if extracted).
    """
    logger.debug("Parsing PDF file with new marker 1.7.4 API")
    
    # Save PDF bytes to a temporary file since PdfConverter expects a file path
    temp_pdf_path = f"/tmp/temp_pdf_{int(time.time())}.pdf"
    try:
        with open(temp_pdf_path, "wb") as f:
            f.write(pdf_file)
        
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
        full_text, _, images = text_from_rendered(rendered)
        metadata = rendered.metadata
        
        logger.debug(f"Images extracted: {list(images.keys())}")
        
        # Process images if needed
        image_data = {}
        if extract_images:
            for filename, image in images.items():
                logger.debug(f"Processing image {filename}")
                
                # Convert image to base64
                byte_stream = io.BytesIO()
                image.save(byte_stream, format=settings.OUTPUT_IMAGE_FORMAT)
                image_base64 = base64.b64encode(byte_stream.getvalue()).decode(
                    settings.OUTPUT_ENCODING
                )
                image_data[filename] = image_base64
        
        return full_text, metadata, image_data
        
    finally:
        # Clean up temporary file
        if os.path.exists(temp_pdf_path):
            os.remove(temp_pdf_path)


# Function to process a single PDF file
def process_pdf_file(file_content: bytes, filename: str, model_list):
    """
    Function to process a single PDF file using new marker 1.7.4 API.

    Args:
    file_content (bytes): The content of the PDF file.
    filename (str): The name of the PDF file.
    model_list: The loaded model dictionary.

    Returns:
    dict: A dictionary containing the filename, markdown text, metadata, image data, status, and processing time.
    """
    entry_time = time.time()
    logger.info(f"Entry time for {filename}: {entry_time}")
    
    try:
        markdown_text, metadata, image_data = parse_pdf_and_return_markdown(
            file_content, extract_images=True, model_list=model_list
        )
        completion_time = time.time()
        logger.info(f"Model processes complete time for {filename}: {completion_time}")
        time_difference = completion_time - entry_time
        
        return {
            "filename": filename,
            "markdown": markdown_text,
            "metadata": metadata,
            "images": image_data,
            "status": "ok",
            "time": time_difference,
        }
    except Exception as e:
        logger.error(f"Error processing {filename}: {str(e)}")
        completion_time = time.time()
        time_difference = completion_time - entry_time
        
        return {
            "filename": filename,
            "markdown": "",
            "metadata": {},
            "images": {},
            "status": "error",
            "error": str(e),
            "time": time_difference,
        }
